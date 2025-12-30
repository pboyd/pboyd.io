---
title: "How to avoid one C++ foot gun"
description: C++'s implicit copy and move behavior offer an excellent way to shoot yourself in the foot. Here's an example of how they can create a double-free and how to avoid it.
date: 2024-05-11
draft: false
type: post
---
I don't think C++ is nearly as bad as some people would make you believe, but it has no shortage of ways to shoot yourself in the foot. I recently wrote some code in the pattern of the following snippet:
```C++
class CheeseShop {
    public:
        CheeseShop(){}
        CheeseShop(std::string configPath) {
            auto cfg = toml::parse(configPath);
            auto cheeses = toml::find<std::vector<std::string>>(cfg, "cheeses");
            for (auto name : cheeses)
                inventory.insert(name);
        }

        std::string gotAny(std::string cheeseName) const {
            return inventory.count(cheeseName) == 1 ? "Yes" : "No";
        }

    private:
        std::unordered_set<std::string> inventory;
};

int main() {
    CheeseShop shop;
    try {
        shop = CheeseShop{"config.toml"};
    } catch(std::exception &e) {
        // Silently continue anyway..
    }

    std::cout << "Red Leicester? " << shop.gotAny("Red Leicester") << std::endl;
    std::cout << "Tilsit? " << shop.gotAny("Tilsit") << std::endl;
    std::cout << "Wenslydale? " << shop.gotAny("Wenslydale") << std::endl;
    std::cout << "Cheddar? " << shop.gotAny("Cheddar") << std::endl;

    return 0;
}
```
[Source](https://github.com/pboyd/cheeseshop/blob/ex1/cheeseshop.cpp)

A more experienced C++ programmer can probably see right away what an idiot I'm being, but I was just happy to see it compile and run:
```
Red Leicester? No
Tilsit? No
Wenslydale? No
Cheddar? No
```

I was less happy after I extended it:
```C++
class CheeseShop {
    public:
        CheeseShop() :
            clerkName{nullptr} {}
        CheeseShop(std::string configPath) :
            clerkName{nullptr}
        {
            auto cfg = toml::parse(configPath);

            auto cheeses = toml::find<std::vector<std::string>>(cfg, "cheeses");
            for (auto name : cheeses)
                inventory.insert(name);

            if (cfg.contains("clerk")) {
                clerkName = new std::string{toml::find<std::string>(cfg, "clerk")};
            }
        }

        ~CheeseShop() {
            if (clerkName)
                delete clerkName;
        }

        std::string gotAny(std::string cheeseName) const {
            if (clerkName && cheeseName == *clerkName)
                return "Sir?";

            return inventory.count(cheeseName) == 1 ? "Yes" : "No";
        }

    private:
        std::unordered_set<std::string> inventory;
        std::string *clerkName;
};
```
[Source](https://github.com/pboyd/cheeseshop/blob/ex2/cheeseshop.cpp)

I added a pointer to my class, and I did it carefully (initialized it to `nullptr`, allocated in the constructor, and de-allocated in the destructor), but it fails catastrophically:
```
Red Leicester? No
Tilsit? No
Wenslydale? No
Cheddar? No
free(): double free detected in tcache 2
Aborted
```

Of course, that's only one possible outcome. It could also segfault, or it may even run fine. Aside from the crash, it's also buggy: my [config file](https://github.com/pboyd/cheeseshop/blob/ex2/config.toml) set the clerk's name to "Wenslydale," so it should have printed "Wenslydale? Sir?" instead of the generic "No." This is the sort of thing that makes people hate C++. I followed an existing working pattern to add a new field. Why should it break? And break so badly at that?

The trouble starts here:
```C++
    CheeseShop shop;
    try {
        shop = CheeseShop{"config.toml"};
    } catch(std::exception &e) {
        // Silently continue anyway..
    }
```

In my mind, I reserved memory for `shop` outside the `try` block, and then I called the constructor to initialize it. But that's not what happens. C++ actually generates code roughly equivalent to:
```C++
    CheeseShop shop{};
    try {
        CheeseShop tmp{"config.toml"}
		// Implicit copy:
        shop.inventory = tmp->inventory;
        shop.clerkName = tmp->clerkName;
        // In the destructor:
        delete tmp->clerkName;
    } catch(std::exception &e) {
        // Silently continue anyway..
    }
```

Space for `shop` is allocated on the stack, and the default constructor for `CheeseShop` initializes it. Inside the `try` block, it makes another instance of `CheeseShop` using the other constructor overload. Since this second instance only exists briefly, C++ will prefer the move assignment operator over the copy operator, but either would work as far as it's concerned. Of course, I didn't overload the copy or move operator, so C++ uses its implicit implementation that copies each field. Finally, the temporary instance falls out of scope, and its destructor is called.

So, both instances have a `clerkName` pointer to the same address on the heap. The temporary instance's destructor frees it, but `shop` hangs onto the pointer to the freed memory. The first version of this program worked because `inventory` is a `std::unordered_set`, which correctly implements move and copy.

In this case, the implicit copy/move behavior is dead wrong. But that behavior makes perfect sense if you remember that one of C++'s design goals is compatibility with C, and that's what C does for struct assignment. The crux of the issue is the trade-offs required to give a C struct the ability to deconstruct itself. Fortunately, C++11 gave us a workaround:
```C++
        CheeseShop(CheeseShop &other) = delete;
        CheeseShop(CheeseShop &&other) = delete;
        CheeseShop &operator=(CheeseShop &other) = delete;
        CheeseShop &operator=(CheeseShop &&other) = delete;
```
[Source](https://github.com/pboyd/cheeseshop/blob/ex3/cheeseshop.cpp)

I add this to every class I write now except for plain old data (POD) structs. I don't love the boilerplate, but I'll live with it because compile errors are much easier to debug than a double-free or a segfault. If I had added it to the first version of the `CheeseShop` class, my compiler (GCC in this case) would have complained:
```
cheeseshop.cpp: In function ‘int main()’:
cheeseshop.cpp:49:40: error: use of deleted function ‘CheeseShop& CheeseShop::operator=(CheeseShop&&)’
   49 |         shop = CheeseShop{"config.toml"};
      |                                        ^
cheeseshop.cpp:31:21: note: declared here
   31 |         CheeseShop &operator=(CheeseShop &&other) = delete;
      |                     ^~~~~~~~
```

That error tells me exactly which method to implement or avoid calling. In this case, I think providing a correct implementation of the move assignment operator is appropriate:
```C++
        CheeseShop &operator=(CheeseShop &&other) noexcept {
            inventory = std::move(other.inventory);
            if (clerkName)
                delete clerkName;
            clerkName = other.clerkName;
            other.clerkName = nullptr;
            return *this;
        }
```
[Source](https://github.com/pboyd/cheeseshop/blob/ex4/cheeseshop.cpp)

With that, we have a working program:
```
Red Leicester? No
Tilsit? No
Wenslydale? Sir?
Cheddar? No
```

Of course, there are other ways to fix this program. They boil down to making the implicit copy safe or avoiding it altogether:

- Make `clerkName` a smart pointer
- Does `clerkName` need to be a pointer at all?
- Make `shop` a pointer to delay initialization

The other way to avoid a double-free is to avoid even a single free. This is sloppy, and I think you should have a little respect for your work, but for an object that lives as long as the program, it doesn't really matter. Also, leaks are preferable to vulnerabilities. So do what you have to do, I just hope I don't have to work with it later.

---

- The original version of the move operator had a memory leak. Thanks to [Gerrit0](https://github.com/Gerrit0) for [reporting](https://github.com/pboyd/cheeseshop/issues/1) the issue.
