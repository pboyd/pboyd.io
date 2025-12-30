---
title: "Kinda okay generated text"
date: 2018-10-04T10:26:00Z
draft: false
type: post
discussions:
- url: https://news.ycombinator.com/item?id=18138628
  site: Hacker News
---

I recently wrote a [Markov chain package](https://github.com/pboyd/markov)
which included a random text generator. The generated text is not very good.
Here's a sample, based on [War and
Peace](https://www.gutenberg.org/ebooks/2600):

> everything Make way to a child till late and was ready or to crush the Kiev
> And what he said Prince I will write a leather apron under this We shall go
> and pressed close up that’s why they are you spent every word from advancing
> to write to prevent his whole army their guilt which the wounded yet dies as
> he exclaimed Natásha of the mountains of the inn they all and to Znaim road
> crossed himself up to the midst of musketry on the big windows The major
> quietly with cards with his lips a bleeding and all 

It's just bad. Lips a bleeding and all.

I don't have a good excuse to make a random text generator. They're silly and
mostly useless. But since I already made one, I might well make a better one.
Here's what I ended up with:

> It flopped into something moist, and the Moscovites who took their opinions
> from others-- Ilyá Rostóv among them-- remained for a long time settling into
> her place. Natásha involuntarily gazed at that neck, those shoulders, and
> chest and stomach involuntarily protruding, had that imposing and stately
> appearance one sees in very young children and very old people was
> particularly evident in her. Then it would suddenly seem to him that his
> long-felt wish, which constitutes the sinew of war, but only talked, and
> seldom listened; now he seemed to see through him, and it was with this that
> Daniel's voice, excited and dissatisfied, interrupted by another, especially
> in clothes that were still moist.

I wouldn't read a book of it, but it's kinda okay. If you need a random text
generator, give it try:
[github.com/pboyd/randtxt](https://github.com/pboyd/randtxt)

The rest of this post covers the evolution of the main algorithm.

## Parts of speech

My first thought to fix the generated text was to use a part of speech (POS)
tagger and insert tagged words into the chain. If you remember diagramming
sentences in grade school, POS tagging mostly the same. The tagger takes some
text, say:

> It's not a question of where he grips it! It's a simple question of weight
> ratios! A five ounce bird could not carry a 1 pound coconut.

And tags the parts of speech:

> It/PRP 's/VBZ not/RB a/DT question/NN of/IN where/WRB he/PRP grips/NNS it/PRP
> !/. It/PRP 's/VBZ a/DT simple/JJ question/NN of/IN weight/NN ratios/NNS !/.
> A/DT five/CD ounce/NN bird/NN could/MD not/RB carry/VB a/DT 1/CD pound/NN
> coconut/NN ./.

(See [here](https://www.ling.upenn.edu/courses/Fall_2003/ling001/penn_treebank_pos.html) for a list of tags.)

It isn't perfect (e.g. "grips" is a verb in the first sentence). But I hoped it
would it would lead to generated text that made more sense.

I experimented with a few POS taggers. For example, here's text generated from
a chain tagged by [NLTK's](http://www.nltk.org) default POS tagger:

> Well you do not at the situation genius utilized the Peace of the service A
> murmur of the Moscow to congratulate Your Majesty From the truly ... Pierre
> He replied the village they fled across the military council was surrounded
> by giving final orders to them silently at that was a very prince who get
> what he came upon his battalion rushes straight up to cry on them to Alpátych
> was purely out of bathing and ruined and wishing for what happened not
> understand why for had not be his old countess instigation gathered round as
> if at the very 

And here's the [Stanford POS
Tagger](https://nlp.stanford.edu/software/tagger.shtml):

> he had been promoted to unite them. he could be too simple and since he was
> in French circle, took him with her dancing hall, too oppressive and burst in
> his pockets and again. Do you, in the piano in a map. know him with her
> mother's room. Someday I have seen in chief. Not only redder than an officer
> was in the prospective purchaser was accepted. he could hear the work of
> Natásha was vaguely affectionate

And [gopkg.in/jdkato/prose.v2](https://godoc.org/gopkg.in/jdkato/prose.v2):

> and many of boxes and began thinking of the Russians , that dreadful if he
> kept asking the commissioner , he 'll have quite useless to seem to the icon
> that prayer . " But his exceedingly lofty , remember what they will remain .
> When your children and then . His whole bosom , the way that he shouted , I
> ? What a thousand men , obviously did not need to Moscow had looked the
> significance of marriage occupied , " said to the policeman , outflankings ,
> last seen the portmanteau and even thought she knew 

(Apologies for the differences in punctuation, I was also working on that at
time.)

POS tagging doesn't seem to make much difference. Theoretically, it should
matter, so I've continued to do it.

## N-grams

The biggest problem is that the generator chooses the next word based only the
previous word. Which is why there are phrases like "I will write a leather
apron". Each pair of words makes sense, but it's nonsense when strung together.

N-grams are one way to fix that. The idea is to split the text into *N* word
chunks, usually 2 or 3 words but sometimes more. For example, take the first
sentence from War and Peace:

> Well, Prince, so Genoa and Lucca are now just family estates of the Buonapartes.

Ignoring punctuation, when *N=2* that's: `Well Prince`, `Prince so`, `so
Genoa`, `Genoa and`, `and Lucca`, etc.

And *N=3* is `Well Prince so`, `Prince so Genoa`, `so Genoa and`, etc.

I didn't want to do it that way, because it produces duplicate words. But I did
a quick test where *N=2* and manually removed the duplicates:

> Prince Vasíli announced his hopes and wishes about it , but it wo n't lack
> suitors . " What an argumentative fellow you are in it a new , envious glance
> at all surprised by what he had continually sought to substitute republican
> for monarchical institutions . These reasons were very insufficient and
> obscure , impalpable , and by the position of the victory and no clear idea
> of letting her slender arms hang down as if struggling with himself that it
> was in high spirits . " " So you are welcome to anything—we shall be our last

It's better. I probably should have kept it that way. But to simplify the
code, I opted for "non-overlapping N-grams". That is dividing the text into
even size chunks like `Well prince`, `so Genoa`, `and Lucca`, etc. Here's the
generated text from that (*N=2* again):

> Prince , de Hohenlohe , and now with his right hand the squadron over to the
> cottage he occupied with learning : that is impossible for them not to unload
> the carts must be a wonderful raconteur , " said he to go up for examination
> ? " " Mon très préopinant"—"My very honorable opponent " ) , and then more
> confident of victory than the winning of two or three friends—you among
> them—and as for the success of one army against another is the duty of Rhetor

And *N=3*:

> , so Genoa and Lucca are now just family estates of the Buonapartes . But I
> warn you that if you dare to play the fool in my presence , I will teach you
> to behave yourself . " But Rostóv bowed himself away from the deepest
> reflections to say a civil word to someone who comes in and can then return
> again to his own . The Emperor proposes to give all commanders of divisions
> the right to shoot marauders , but I cannot say so , judging by what the
> doctor said , it was witty and  

*N=3* looks great. But it actually just strung together large chunks of input
text. For example, "right to shoot" only occurs once in War and Peace:

> The Emperor proposes to give all commanders of divisions the right to shoot
> marauders, but I much fear this will oblige one half the army to shoot the
> other.

That's not exactly random.

But *N=2* worked alright. And after cleaning up the punctuation and
capitalization, I ended up with text like:

> No, I won't promise. There was a ford one third of a regiment of Foot Guards
> he heard a tread of heavy boots and with belts and girdles tightened, were
> taking leave of her. At length appears the lieutenant general, our life is to
> love God. He does not want to.

If it seems disjointed that's because I was feeding punctuation into the chain
as independent entities. So the text after every period or comma had nothing to
do with the text before it.

## N-grams, take 2

I was going to call *N=2* non-overlapping n-grams good enough, but I found a
[paper](https://arxiv.org/pdf/1601.03313v2.pdf) from Valentin Kassarnig on
generating congressional speeches. He was trying to generate a speech for or
against particular issues, and he didn't use a Markov chain, so it's not really
the same thing. But what stuck out to me was that he used four words to choose
the next one. I suppose this is the correct way to use n-grams.

The algorithm takes 4 words as a seed, say:

> strange/JJ women/NNS lying/VBG in/IN

Which is used to pick the next word, `ponds/NNS`. And the seed for the word
after is:

> women/NNS lying/VBG in/IN ponds/NNS

The process continues like that, new words are added to the end and old ones
are dropped from the beginning.

This was the result when I tried it with *N=5*:

> Genoa and Lucca are now just family estates of the Buonapartes . but I warn
> you , if you do n't feel strong enough to control yourself , she would reply
> sadly , trying to comfort her husband . among the gentry of the province
> Nicholas was respected but not liked . he did not concern himself with the
> interests of his own class , and consequently some thought him proud and
> others thought him stupid . the whole summer , from spring sowing to harvest
> , he was busy with the work on his farm . in autumn he gave himself up to

Unfortunately, it's just copying the book again. Everything after "if you
don't" is a verbatim copy.

The problem is that 4 word sequences are frequently unique in my dataset.
Kassarnig used a bag of words (that is, ignored the order) to pick the next
word (he joined them back together at the end), which should have reduced the
number of unique phrases. He also had a larger dataset, and congressional
speeches are repetitive anyway, so it may have not been an issue.

But *N=3* works pretty well for me:

> ? I would have offered you something . they 'll cweep up to the road which
> gleamed white in the mist with a plaintive sound passed out of hearing .
> another musket missed fire but flashed in the pan . Rostóv turned his horse
> about and galloped off . but no , it should be , to avoid misunderstandings ,
> that you must apologize to the colonel gave Pierre an angry look and wanted
> to put up with ... . is everything quite all right ? said the old count felt
> this most . he would make that foxy old courtier feel that the childish

(And, yes, the book does include "cweep".)

That's the algorithm I'm stopping with. The text is still obviously
auto-generated, which I'm a bit disappointed with. But it might be fine for
test data or placeholder text which just needs a realistic facade.
