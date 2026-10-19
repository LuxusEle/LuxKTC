# SketchUp Project Studio

The Ruby extension has its own local `UI::HtmlDialog` interface. Its HTML, CSS and JavaScript live in `app/studio.*`; Ruby handles project generation and the shared HTTP API. The panel does not load the web page or expose API keys.

## Open it

Keep the LuxKTC local service running for project creation, synchronization and quote previews. Restart `Start-LuxKTC.cmd` after this update so the new preview route is available. Then load the current checkout in SketchUp's Ruby Console:

```ruby
load 'C:/Users/asank/.codex/.chatgpt-projects/g-p-680bd904c9948191a5f212831ea92089/LuxKTC/app/aj_board_kitchen.rb'
```

**LuxKTC Project Studio** opens automatically. Reopen it with **Extensions → LuxKTC shared project → Project studio**, or:

```ruby
AJBoardKitchen::Studio.show
```

## Use it without wall photographs

1. Choose **New project → Empty measured project**. You can create the shared project inside SketchUp; no browser project setup is needed.
2. In **Room**, add a wall with width, height, thickness, origin and rotation. Enter millimetres and confirm dimensions when checked on site. A plain wall needs no photo, photo asset ID, perspective correction or AI call. Add openings/services if required.
3. In **Cabinets**, choose units and set their wall, dimensions, placement, connector, hinge and edging options. Open shelves are upper only. Wall-local X runs left to right; Z is measured up from the floor. Base/tall box height excludes the engine's 100 mm plinth.
4. **Build model** applies the form to SketchUp through the existing Ruby engine. It retains the grooved backs, stretchers, side-specific edge deductions, machining and nesting.
5. **Save to web** builds the model and pushes the project using its loaded server revision. The web app reads that same saved project and BOM. A newer server revision is a conflict, not permission to overwrite another client's edits.
6. **Pull web changes** receives the current shared project and any corrected wall textures. It asks before replacing local model edits. Wall photos can be added later in the web interface; they remain optional.

**Read model changes** captures supported native cabinet placements into the form. Edit wall dimensions and openings in the Studio rather than moving or editing the generated wall faces. Reflections, scaling, tilt and freehand part edits cannot safely become parametric machining; the bridge retains the model and reports those unsupported changes.

## BOM, quote and visibility

**BOM & quote** can preview the current form through the real Ruby generator and the server's canonical quantity/pricing functions. The preview does not save the shared project or rebuild the model. Enter your own material/profile/band/hardware rates, labour, markup and tax; an incomplete price list stays unpriced. **Save to web** persists the rates and design.

The Project tab includes visibility controls for walls, room/cabinet dimensions, doors, drawer faces/boxes, connectors, hinges, backs, stretchers, machining, bands, labels and nesting. **Check web** reports a newer shared revision; it does not automatically rebuild an actively edited model. The browser continues to refresh clean drafts from saved SketchUp updates.

## Verification and limits

`app/test/verify_project_ui.rb` tests the real controller/engineering boundary using headless UI and network mocks: project creation, photo-free walls, generated cabinets, canonical preview requests, native position merging, conflicting/stale forms, failed-save correction/retry, canceled pulls, model switching and closed-dialog callbacks. `verify_sync.rb` covers the async HTTP/model bridge, including errors and out-of-order responses. The photo-free API suite also runs actual Ruby jobs without an image or AI request.

These checks do not exercise the installed SketchUp window, CEF rendering or native wall texture geometry. Native application testing remains necessary; the earlier automatic approval rejection for browser helpers was not bypassed.
