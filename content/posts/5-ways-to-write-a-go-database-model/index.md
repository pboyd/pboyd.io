---
title: "5 Ways to Write a Go Database Model"
description: Choosing the right tools to write a database model in Go can be overwhelming. This post describes the various approaches.
date: 2023-07-12
draft: false
type: post
image: gopher-db.png
image_caption: A gopher and a database.
discussions:
- url: https://www.reddit.com/r/golang/comments/14yh7y0/5_ways_to_write_a_go_database_model/
  site: /r/golang
---
{{< autoimg src="gopher-db-small.png" alt="A gopher and a database." >}}
When I interview software developers, one of my go-to icebreakers is, "How did you get started in programming?" Sometimes the answer is that the candidate just had to declare a major. Which is fine--it's just an icebreaker. But the responses I like most are about the candidate's earliest project. The one that made them want to a programmer. The project varies, but it's always fun--often a video game. So far, no one ever told me they became a programmer to write database models. And, yet, if you make web apps, you will spend more time on database models than the fun stuff that made you want to be a programmer.

If your app were a meal, the database models are like a bland carb that fills your belly but never satisfies. They are, well, crud. So it's no wonder that Go has so many tools to get this job out of the way. It's great to have options, but there are so many options that it can be overwhelming. This post looks at a few categories of tools, with examples of each, so you can pick the right approach for your project.

The sample code is on [GitHub](https://github.com/pboyd/godbmodels/). Each variant covered here has the same functionality, namely, [CRUD](https://en.wikipedia.org/wiki/Create,_read,_update_and_delete) operations for one table of a [fan database for Monty Python and the Holy Grail](https://github.com/pboyd/godbmodels/blob/master/common/grail.sql). I'm also sticking to relational databases.

## Vanilla
We'll get to fancy tools in a moment, but first, we need a baseline. Since all you need is a database driver and the standard library, that's all that the first [example](https://github.com/pboyd/godbmodels/blob/master/vanilla/characters.go) uses.

I opted to make the model itself a plain data struct and wrote a `CharacterStore` struct to perform the CRUD operations:
```Go
type Character struct {
	ID      int64
	ActorID int64
	Name    string
}

type CharacterStore struct {
	db *sql.DB
}
```

The methods on `CharacterStore` are probably what you expect:
```Go
func (cs *CharacterStore) Get(ctx context.Context, id int64) (*Character, error) {
	row := cs.db.QueryRowContext(ctx, `SELECT id, actor_id, name FROM characters WHERE id = $1`, id)

	var c Character
	err := row.Scan(&c.ID, &c.ActorID, &c.Name)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}

	return &c, err
}
```

The only method that's a bit different is `List`, which searches by various criteria. Here's the interface:
```Go
type CharacterFilters struct {
	// ActorID matches on the actor's ID.
	ActorID int64

	// ActorName does a case-insensitive partial match on the actor name.
	ActorName string

	// Name does a case-insensitive partial match on the character name.
	Name string

	// SceneNumber filters by the scene that the character appears in.
	SceneNumber int64
}

func (cs *CharacterStore) List(ctx context.Context, filters *CharacterFilters) ([]*Character, error) {
...
}
```

The [implementation](https://github.com/pboyd/godbmodels/blob/master/vanilla/characters.go#L115C4-L115C4) builds the SQL query in a string, and it's a bit of a mess.

This approach has the obvious downside that the code is tedious to write. It can also be error prone (for instance, matching the columns in your query to the order in `Scan`). But you have absolute control over every aspect.

## Struct Mappers
Sometimes you may want just a bit more than the standard library offers. This is where a package that can map between SQL and a struct comes in. There are a few similar packages ([1](https://github.com/blockloop/scan) [2](https://github.com/georgysavva/scany), [3](https://gitlab.com/qosenergy/squalus)), but I've used [`sqlx`](https://github.com/jmoiron/sqlx) for an [example](https://github.com/pboyd/godbmodels/blob/master/mapper/characters.go). Most of these tools, and `sqlx` in particular, use reflection to automate the most tedious parts of the vanilla approach.

Our `Character` struct gets a few `db` tags:
```Go
type Character struct {
	ID      int64  `db:"id"`
	ActorID int64  `db:"actor_id"`
	Name    string `db:"name"`
}
```

And that allows us to use `sqlx`'s methods to load data directly into the struct:
```Go
	var c Character
	err := cs.dbx.GetContext(ctx, &c, `SELECT id, actor_id, name FROM characters WHERE id = $1`, id)
```

You can use the field's tag name in queries too:
```Go
	res, err := cs.dbx.NamedExecContext(ctx, `UPDATE characters SET actor_id = :actor_id, name = :name WHERE id = :id`, c)
```

This is good when you want to keep most of the control, but you would like to avoid writing yet another `for rows.Scan()` loop.

The only drawback I've found is that the fields in your data structs frequently need to implement [`Scanner`](https://pkg.go.dev/database/sql#Scanner) and [`Valuer`](https://pkg.go.dev/database/sql/driver#Valuer). It's avoidable, but this commonly means exposing `sql.NullString` or [`pq.StringArray`](https://pkg.go.dev/github.com/lib/pq#StringArray) to parts of the codebase that are otherwise ignorant of the database.

## SQL Builders
If you're tired of handwriting SQL queries, try a SQL generator. I'm using [`squirrel`](https://github.com/Masterminds/squirrel) for this post, but there are a few similar packages (such as `squirrel`'s cousin [`sqrl`](https://github.com/elgris/sqrl)). Here's the example code: [`builder/characters.go`](https://github.com/pboyd/godbmodels/blob/master/builder/characters.go).

If you recall the `Get` method from the vanilla example, it has been simplified to:
```Go
func (cs *CharacterStore) Get(ctx context.Context, id int64) (*Character, error) {
	var c Character
	err := squirrel.
		Select("id", "actor_id", "name").
		From("characters").
		Where("id = ?", id).
		RunWith(cs.db).
		QueryRowContext(ctx).
		Scan(&c.ID, &c.ActorID, &c.Name)

	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}

	return &c, err
}
```

A small improvement, perhaps, but the real advantage is for more complicated queries, such as the `List` method:
```Go
func (cs *CharacterStore) List(ctx context.Context, filters *CharacterFilters) ([]*Character, error) {
	q := squirrel.
		Select("c.id", "c.actor_id", "c.name").
		From("characters c").
		RunWith(cs.db)

	if filters != nil {
		if filters.ActorID != 0 {
			q = q.Where("actor_id = ?", filters.ActorID)
		} else if filters.ActorName != "" {
			q = q.
				Join("actors a ON a.id = c.actor_id").
				Where("LOWER(a.name) LIKE ?", "%"+strings.ToLower(filters.ActorName)+"%")
		}

		if filters.Name != "" {
			q = q.Where("LOWER(name) LIKE ?", "%"+strings.ToLower(filters.Name)+"%")
		}

		if filters.SceneNumber != 0 {
			q = q.
				Join("scene_characters sc ON sc.character_id = c.id").
				Where("sc.scene_id = ?", filters.SceneNumber)
		}
	}

	rows, err := q.QueryContext(ctx)
	// ... same as before from here ...
}
```

This code is still probably too complex, but `squirrel` simplified the [original](https://github.com/pboyd/godbmodels/blob/master/vanilla/characters.go#L115) a lot.

Query generators fit nicely in a mostly vanilla `database/sql` codebase. I have found few downsides, mostly because it's easy to fall back to hand-written SQL.

## `sqlc`
You've seen Go generate SQL, but have you seen SQL generate Go? If not, look at [`sqlc`](https://sqlc.dev/). You write a SQL file with some minimal annotation:
```sql
-- name: GetCharacter :one
-- GetCharacter loads a character from the database by ID.
SELECT * FROM characters WHERE id = ?;
```

And `sqlc` generates Go code:
```Go
// models.go
type Character struct {
	ID      int64
	Name    string
	ActorID int64
}

// characters.sql.go
const getCharacter = `-- name: GetCharacter :one
SELECT id, name, actor_id FROM characters WHERE id = ?
`

// GetCharacter loads a character from the database by ID.
func (q *Queries) GetCharacter(ctx context.Context, id int64) (Character, error) {
	row := q.db.QueryRowContext(ctx, getCharacter, id)
	var i Character
	err := row.Scan(&i.ID, &i.Name, &i.ActorID)
	return i, err
}
```
[Full example](https://github.com/pboyd/godbmodels/tree/master/sqlc).

`sqlc` removes a lot of tedious code without taking any of your control over the SQL. And, unlike every other option in this post, there's no runtime penalty for using it. It takes a bit of configuration to get started (it needs to know your schema, for instance), but after that, you can regenerate the models as often as you want.

The major downside of `sqlc` is that you lose direct control of the interface on the generated code. The code it makes isn't terrible, but it feels a bit mechanical sometimes. Of course, if you really don't like it, you can generate private methods with `sqlc` and wrap them as you want. That's what I did with the `StoreCharacter` method:
```Go
func (q *Queries) StoreCharacter(ctx context.Context, c *Character) error {
	if c.ID == 0 {
		id, err := q.insertCharacter(ctx, insertCharacterParams{
			ActorID: c.ActorID,
			Name:    c.Name,
		})
		if err != nil {
			return err
		}

		c.ID = id
		return nil
	}

	return q.updateCharacter(ctx, updateCharacterParams{
		ID:      c.ID,
		ActorID: c.ActorID,
		Name:    c.Name,
	})
}
```

`insertCharacter` and `updateCharacter` are from `sqlc`.

The other problem is that you're restricted to what you can express in SQL. If you want to build a query based on some optional criteria, like my `List` example, you can't do it. I had to settle for this:
```Go
func (q *Queries) ListCharacters(ctx context.Context, filters *CharacterFilters) ([]Character, error) {
	switch {
	case filters.ActorID != 0:
		return q.listCharactersByActor(ctx, filters.ActorID)
	case filters.ActorName != "":
		return q.listCharactersByActorName(ctx, filters.ActorName)
	case filters.Name != "":
		return q.listCharactersByName(ctx, filters.Name)
	case filters.SceneNumber != 0:
		return q.listCharactersByScene(ctx, filters.SceneNumber)
	default:
		return q.listAllCharacters(ctx)
	}
}
```

Unlike every other implementation of this method, this version can't filter by more than one filter param. It could be done by writing a SQL query for each permutation. I frequently augment what `sqlc` generates, so you're free to use it where it helps and ignore it when it doesn't.

## ORMs
Go has a few ORMs to choose from, though [GORM](https://gorm.io/) is pretty popular, and what I've used for this [example](https://github.com/pboyd/godbmodels/blob/master/orm/characters.go). Like any full-featured ORM, you only have to define the object. Here's the definition for the `Character` struct:
```Go
type Character struct {
	ID      int64  `gorm:"id,primaryKey"`
	ActorID int64  `gorm:"actor_id"`
	Name    string `gorm:"name"`

	Actor Actor
}
```

That's enough for GORM to handle all the CRUD operations, for example to create a new Character:
```Go
	err := db.Create(&Character{
		Name:    "Sir Not-Appearing-in-this-Film",
		ActorID: 1,
	}).Error
```

The `List` method (well, now it's the `ListCharacters` function) looks like the `squirrel` version, except it's a little simpler because GORM handles the `Scan`.

GORM has given us quite a lot for such a small amount of code. But, in exchange, we had to cede control over the interface and the SQL queries. It's a devil's bargain. I avoid ORMs, but if fast development is your primary concern, GORM may be the right choice.

## Wrapping up
I have presented these options as if they exist in a world all their own, but as long as you can get a `sql.DB`, you can mix and match anything. My preferred approach lately has been `sqlc` with `squirrel` where it makes sense. Ultimately, you have to pick the approach that works for your project. ~~And, of course, if you're still overwhelmed, I do consulting.~~

I have barely scratched the surface of database tools in Go. If you want more, try the [Awesome Go](https://github.com/avelino/awesome-go) list (specifically, the [database](https://github.com/avelino/awesome-go#Database) and [ORM](https://github.com/avelino/awesome-go#ORM) sections).

