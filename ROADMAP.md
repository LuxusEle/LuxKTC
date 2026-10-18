# Workshop development notes

Current baseline: `0.4.1-aspire-dxf`. The Aspire R12 exports and separate process layers passed saved-file inspection, but a native Aspire import remains to be confirmed in the workshop.

## Next machining/export revision

- [ ] Use one OUTSIDE_CUT process layer for every part profile in a job, regardless of cabinet or panel type. Keep face/setup and material/thickness available as metadata or separate files without conflating tooling classes.
- [ ] Standardize DRILL and POCKET toolpath layers by actual tool/operation requirements, with diameter and depth where needed. Distinguish through drilling from blind drilling and keep GROOVE as its own operation where used.
- [ ] Confirm production cut sizes after applying selected edgeband thickness on the applicable sides. Record finished size, core cut size, and band allowance separately.
- [ ] Add a simple orientation triangle to the part sticker so operators can align the labeled edgeband sides to the nested panel. Keep labels out of machining toolpaths.
- [ ] Add saved workshop templates for handles, hinges, connector recipes, rail dimensions/patterns, upper/lower carcass board thickness and top/bottom door colours.
- [ ] Validate the exported DXFs in the user's Aspire version with a 100 mm calibration part before promoting a machining file to production.

These are requirements for future development, not claims about the current export behavior.
