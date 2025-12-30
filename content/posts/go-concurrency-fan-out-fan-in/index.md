---
title: "Go Concurrency: Fan-out, Fan-in"
description: Fan-out, fan-in is the work-horse of Go concurrency patterns. This post explains how it works with an example.
date: 2023-07-23
draft: false
type: post
image: flowerbed-mosaic-small.jpg
image_caption: A mosaic of an overgrown flower bed.
discussions:
- url: https://www.reddit.com/r/golang/comments/1586ezi/go_concurrency_fanout_fanin/
  site: /r/golang
- url: https://lobste.rs/s/rr73pz/go_concurrency_fan_out_fan
  site: Lobste.rs
---
{{< autoimg
    src="flowerbed.jpg"
    alt="My overgrown flower bed."
    caption="The flower bed in the front of my house." >}}

Yes, it's overgrown. I'm sure an upstanding citizen concerned with suburban respectability, such as yourself, will agree with my wife that I "should really do something about that." I had plenty of time this week, so naturally, I used that time to ignore the flower bed and write a [mosaic generator](https://github.com/pboyd/mosaic). That way, I can give you this lovely mosaic of my not-so-lovely flower bed:

{{< autoimg
    src="flowerbed-mosaic-small.jpg"
    link="flowerbed-mosaic.jpg"
    alt="A mosaic of my overgrown flower bed."
    caption="Tile images from [Lorem Picsum](https://picsum.photos/images).">}}

That image contains 14,490 tiles made from 894 source images, which takes a lot of processing. Fortunately, much of it can be done concurrently. In fact, the core of this program is two incredibly standard processing pipelines, which are so ordinary that I'm using them as an excuse to talk about the work-horse of Go concurrency patterns: fan-out, fan-in. It's very versatile, you can use for almost any concurrent processing.

Before we get going, I need to explain `mosaic` at a high level. It has two phases: indexing and swapping. Indexing builds a list of tile images for the swap phase. The swap phase finds a replacement for each tile in the output image. Indexing has to finish before swapping can begin, but each phase can proceed concurrently. It looks like this:

{{< autoimg
    src="mosaic-arch-small.png"
    link="mosaic-arch.png"
    alt="Architecture diagram of mosaic" >}}

## Generators
The building blocks of concurrent Go code tend to look like this:
```Go
func counter() <-chan int {
	out := make(chan int)

	go func() {
		defer close(out)

		for i := 0; i < 100; i++ {
			out <- i
		}
	}()

	return out
}
```

This function returns immediately and emits a stream of values to the returned channel. They remind me of generators in Python, so that's what I call them. Concurrency in Go is much easier if you follow two rules: 1) every channel should have only one writer, and 2) that writer must close the channel. This function returns a read-only channel, which prevents any other writes. And the `defer` closes the channel automatically.

Go continues to emit values from closed channels until everything has been consumed, and Go's `for .. range` loop breaks automatically at the end of the channel. So the convention is to consume values from the channel like this:
```Go
for value := range count() {
	// do something with value
}
```

In `mosaic`'s indexer, the first generator in the pipeline emits image file names:
```Go
func (idx *Index) findImages(ctx context.Context, path string) <-chan string {
	ch := make(chan string)
	go func() {
		defer close(ch)

		err := filepath.WalkDir(path, func(path string, d fs.DirEntry, err error) error {
			if err != nil {
				log.Printf("%s: %s", path, err)
				return nil
			}

			ext := strings.ToLower(filepath.Ext(path))
			switch ext {
			case ".jpg", ".jpeg", ".png", ".gif":
			default:
				return nil
			}

			select {
			case ch <- path:
			case <-ctx.Done():
				return fs.SkipAll
			}

			return nil
		})
		if err != nil {
			log.Fatalf("error walking path %s: %s", path, err)
		}
	}()
	return ch
}
```
[source](https://github.com/pboyd/mosaic/blob/v0.9.1/index.go#L106)

The only new wrinkle in the pattern is the context, which I'll talk about in a bit. This function is also very similar to the start of the swap pipeline: [`tileize`](https://github.com/pboyd/mosaic/blob/v0.9.1/mosaic.go#L56).

## Fan-out
Generators are not inherently concurrent: readers wait for input, and writers wait for readers. We could make it concurrent by adding a buffer to the output channel. That may be appropriate for whatever you're building, but it won't help me here. What I need is a function that can run concurrently and analyze images:


```Go
func (idx *Index) worker(ch <-chan string) <-chan imageColor {
	out := make(chan imageColor)
	go func() {
		defer close(out)
		for path := range ch {
			img, err := loadImage(path)
			if err != nil {
				log.Printf("%s: %s", path, err)
				continue
			}

			out <- imageColor{
				Path:  path,
				Color: primaryColor(img, 0.01),
			}
		}
	}()

	return out
}
```
[(source)](https://github.com/pboyd/mosaic/blob/v0.9.1/index.go#L144)

This is yet another generator function. We can run many different copies of it and give each one the same input channel (which is the output from the previous step):
```Go
	colorChs := make([]<-chan imageColor, numberOfWorkers)
	for i := range colorChs {
		colorChs[i] = idx.worker(pathCh)
	}
```

That is the "fan-out" of "fan-out, fan-in." It may take some experimentation to find a good value for `numberOfWorkers`. `runtime.NumCPU()` is a good first guess, especially for CPU-intensive tasks like this one.

`findImages` still blocks, but only until one of the workers is ready for another value. The workers will also block if the input channel is empty or the output channel is full. The goal is to prevent either of those things from happening so that data flows through and work proceeds concurrently.

## Fan-in
A slice of channels is cumbersome to use. You might think `select` could help, but that requires explicitly naming the channels in the code. You may also be tempted to try something like this:
```Go
for i := range sliceOChannels {
	for value := range sliceOChannels[i] {
		// Do something with value
	}
}
```

But don't do that. In the best case, your channels are buffered and have enough capacity for all your output, so you waste memory. In the worst case, your program blocks workers `i+1..n` while processing values from worker `i`. That's not concurrency. It's complicated serial code.

The indexer needs to get these back to a single output stream because its "index" is a slice, which can't be modified concurrently (a mutex would work too, but it's less elegant and still not concurrent). This channel merge is "fan-in":

```Go
func mergeColorChannels(chs ...<-chan imageColor) <-chan imageColor {
	out := make(chan imageColor)

	var wg sync.WaitGroup
	wg.Add(len(chs))
	for _, ch := range chs {
		go func(ch <-chan imageColor) {
			defer wg.Done()
			for img := range ch {
				out <- img
			}
		}(ch)
	}

	go func() {
		wg.Wait()
		close(out)
	}()

	return out
}
```
[(source)](https://github.com/pboyd/mosaic/blob/v0.9.1/index.go#L169)

Hopefully, you recognize the generator function. This one takes any number of input channels, and instead of starting one goroutine, it has `n+1` goroutines. Remember our rule that each channel should have one writer? We fudge it a little here by having multiple goroutines write to the same output channel, but we can say that our merge function is still the only writer.

The `WaitGroup` ensures we follow our 2nd rule: the writer must close the channel. Yes, it's tedious code. But if we didn't close the channel, the consumer wouldn't know when to terminate, and the program would hang.

It may seem wasteful to make this many goroutines. If they were threads or, heaven forbid, processes, you'd be right. But goroutines are cheap, and these mostly block waiting for input.

The final step in our indexing pipeline is to read values off one at a time:
```Go
	for found := range mergeColorChannels(colorChs...) {
		idx.insert(found.Color, found.Path)
	}
```

This has the additional effect of preventing our main index function from returning until everything has been processed.

By the way, the merge is why this algorithm is concurrent, not parallel. Each worker can work independently, but it eventually has to wait its turn for `insert`. The swap phase of `mosaic` skips the merge because each worker can write directly to its tile in the output image, so it _might_ be parallel depending on available CPU cores and scheduling.

> Concurrency is two lines of customers ordering from a single cashier (lines take turns ordering); Parallelism is two lines of customers ordering from two cashiers (each line gets its own cashier).
> {{< br >}}
> {{< br >}}
>   -- Ancient Chinese Proverb (or was it [chharvey on Stack Overflow](https://stackoverflow.com/questions/1050222/what-is-the-difference-between-concurrency-and-parallelism)?)

## Closing
The first generator finishes its work and closes its output channel, which signals the workers in the next step to finish. This continues down the line until the final output channel is done. So, in the end, the whole pipeline folds in on itself quite gracefully. You may also recall that the first generator in our pipeline took a context:

```Go
func (idx *Index) findImages(ctx context.Context, path string) <-chan string {
	ch := make(chan string)
	go func() {
			// ...
			select {
			case ch <- path:
			case <-ctx.Done():
				// Abort
				return fs.SkipAll
			}
			// ...
	}()
	return ch
}
```

You may have noticed that none of the other generators took a context. That's because each piece of work was small enough that it might as well finish it. All we have to do to cancel is stop the input stream at the head, and let the pipeline shut down as normal.

In `mosaic`, the context is closed by an interrupt handler:
```Go
ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt)
defer cancel()
```

The upshot is that interrupting `mosaic` with `Ctrl-C` when in its swapping phase will cause it to finish anything in progress and write a partially completed image. The way these pipelines end is a beautiful feature of Go concurrency and one of my favorite things about the language.
