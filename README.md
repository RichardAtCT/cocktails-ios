# Decent Cocktails for iPhone, iPad and Mac

A native SwiftUI app of [Decent Cocktails](https://decentespresso.com/cocktails/): cocktail recipes from *The PDT Cocktail Book* and *Death & Co: Modern Classic Cocktails*, each ingredient weighed in grams and made to be mixed on the [Half Decent Scale](https://decentespresso.com/scale).

The app is a copy of the website, page for page. It ships with the books' databases and pictures, so it works without a network connection.

Status: a work in progress, not yet in the App Store. It runs as a Mac Catalyst app (for debugging) and on iPhone and iPad.

## What it does

- **Browse:** choose a book, then browse its cocktails by popularity, A–Z, base spirit or sweetness, by spirit and spirit pairs ("gin + Campari"), by ingredient and ingredient type, and by glass. Search covers drinks, ingredients and spirit types.
- **Recipes:** every step in grams (and ounces), the glass and method, and Decent's own description. Each recipe also has alcohol, sugar and acid figures, similar cocktails with how they differ, and the same drink in the other book.

Planned:
- members' features: Your Bar, the Wishlist and Made lists, shared with the website
- making a drink step by step on the Half Decent Scale over Bluetooth
- translations into the site's languages
- iPad polish

## Building

You need Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
scripts/sync_data.sh
```

```bash
xcodegen generate
```

```bash
xcodebuild -scheme Cocktails -destination 'platform=macOS,variant=Mac Catalyst' -derivedDataPath build CODE_SIGN_IDENTITY=- build
```

Or open `Cocktails.xcodeproj` in Xcode and run on an iPhone simulator or "My Mac (Mac Catalyst)".

`scripts/sync_data.sh` copies the data into `Resources/Data/`:
- the two book databases (`pdt.db`, `deathco.db`, SQLite)
- the taste and substitute notes (JSON)
- the AVIF pictures

These come from the website's source tree (`/d`), which is not public. That is why the data is not in this repository (see Licence).

## How it is put together

```
project.yml              XcodeGen spec; the .xcodeproj is generated from it
Sources/
  CocktailsApp.swift     the app, the navigation stack, deep links, the book header
  Data/
    SQLite.swift         a small read-only SQLite wrapper
    Books.swift          the books (as pdt_books on the site)
    Store.swift          a book's queries: spirits, categories, glasses, search, cards
    Recipe.swift         one recipe: the steps in grams, serve row, facts, similar drinks
    Img.swift            where pictures are (the db's image column)
    Lang.swift           translation lookup (English for now)
  UI/
    Theme.swift          the site's colours and fonts, light and dark
    Route.swift          every page as a route, and site URL → route
    Components.swift     cards, chips, grids, section heads
  Screens/               the pages: home, lists, recipe
scripts/
  sync_data.sh           copy the dbs and pictures from the site's tree
  shot.sh                screenshot any page of the Mac build: shot.sh /cocktails/pdt/recipes/Negroni out.png
```

Each page runs the same SQL as the website's page (`lib/direct.tcl` on the site), so the two list the same drinks in the same order. The app takes the site's paths as deep links and as a launch argument:

```bash
build/Build/Products/Debug-maccatalyst/Cocktails.app/Contents/MacOS/Cocktails -open /cocktails/deathco/spirit/gin
```

Pictures are named by the `image` column of the `drink`, `ingredient` and `glass` tables: the path below `cocktails/img/` without the extension, e.g. `deathco/negroni`. The [API guide](https://decentespresso.com/cocktails/api/) lists every size and copy of a picture.

## Licence

The **app's source code** is licensed under the GNU General Public License, version 3: see [LICENSE](LICENSE).

The licence covers the code only, not the data the app ships with:
- **Decent's own content:** the drink descriptions, comparisons and taste notes, method wording, computed figures, and the AI-generated drink and glass pictures. It is Creative Commons Attribution 4.0 ([CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)), credit "Decent Cocktails (decentespresso.com/cocktails)".
- **The recipe facts:** drink names, ingredients and amounts, glass, garnish and creator credits. They come from the books, and Decent claims no rights in them. Please buy the books.
- **Ingredient pictures:** many are product photographs, or drawn from them, and show the makers' labels. They are not licensed for reuse.
- **Fonts:** [Archivo](https://fonts.google.com/specimen/Archivo) and [IBM Plex Mono](https://fonts.google.com/specimen/IBM+Plex+Mono), under the SIL Open Font License 1.1.

To build your own app from the same recipes, use the public [Decent Cocktails API](https://decentespresso.com/cocktails/api/) or its [MCP server](https://decentespresso.com/cocktails/mcp).

© Decent Espresso Ltd
