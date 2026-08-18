# Generator Inline Results Design QA

## Latest change

- Source visual truth: `artifacts/design-qa/generator-inline-results-reference.png`
- Implementation screenshot: `artifacts/design-qa/generator-inline-results-implementation.png`
- Side-by-side comparison: `artifacts/design-qa/generator-inline-results-comparison.png`
- Source pixels: 1478 × 1316
- Implementation pixels / viewport: 1224 × 768 at 76% canvas zoom
- State: light appearance, one existing generated image, one reference image, editable prompt, four-images-per-run selected.

The separate canvas result group has been removed. The generated image now remains inside the generation composer, the visible generator name and rename affordance are gone, and the footer exposes a compact 1–4 output-count selector. A single result is shown directly; a batch of 2–4 results adds a rectangular thumbnail strip at the top of the node and clicking a thumbnail switches the main image without creating canvas nodes or result groups.

The current project only contains one historical result, so the runtime screenshot intentionally shows the one-result state without a redundant thumbnail strip. The multi-result state is driven by the latest succeeded or partially succeeded GenerationRecord, is capped at four assets, and has a dedicated clickable thumbnail implementation. The generation pipeline and persistence regression suite passed with 241 tests.

No actionable P0, P1, or P2 findings remain for this change.

## External result history correction

- Verified screenshot: `artifacts/design-qa/generator-external-history-implementation.png`
- Viewport: 1224 × 768 at 64% canvas zoom
- Real persisted state: 3 generation batches containing 1 + 4 + 3 images (8 total).

Result choices now live outside the generator body in rows above it. Each GenerationRecord becomes one row with at most four 16:9 thumbnails; a later generation appends another row instead of replacing the previous row. In the verified project all three historical batches are simultaneously visible. Clicking an older thumbnail selects it and switches the large preview in the generator without creating a canvas image node or restoring the removed result-group container.

The external shelf remains derived presentation chrome: the generator's persisted frame, resize handles, reference connection anchors, copying, deletion, and layer identity are unchanged. Its culling shell expands upward by the exact number of historical rows so the thumbnails do not disappear merely because their parent node frame is outside the ordinary culling rectangle.

## Single-row scrolling result rail

- Runtime state: 3 historical batches, 8 images total.
- The former stacked rows are flattened into one chronological horizontal rail above the node.
- New results append at the right edge and the rail automatically reveals the newest result.
- Horizontal trackpad movement over the rail scrolls the thumbnails; vertical movement and gestures outside the rail continue to pan the infinite canvas.
- Only the fixed one-row viewport contributes to culling geometry, so a long history does not enlarge the generator's canvas selection bounds.

- Source visual truth: `artifacts/design-qa/generator-simplification-source.png`
- Final implementation screenshot: `artifacts/design-qa/generator-simplified-final.jpeg`
- Focused comparison: `artifacts/design-qa/generator-simplification-final-comparison.png`
- Source pixels: 812 × 1228
- Implementation pixels / viewport: 1224 × 768; the canvas was set to 64% so the complete generator node and its surrounding relationship were visible.
- Density normalization: the focused implementation crop and source were normalized to a shared 902 px comparison height. The source is a before-state reference rather than a target to reproduce exactly.
- State: light appearance, existing image-generation node with one image reference, empty prompt, idle generation state. The persisted node still has a 1:1 generation parameter, while the empty media stage intentionally uses the new independent 16:9 fallback.

## Full-view comparison evidence

The final canvas capture shows that the generator remains legible as a single object at 64% zoom, with the image reference line still terminating at the node and the image/text nodes retaining their original interaction geometry. The image-generation stage is now the visual focus rather than the settings controls.

## Focused-region evidence

The focused side-by-side comparison isolates the generator node. The before-state has a square output viewport plus an outlined composer card containing additional outlined controls. The final implementation has a wide 16:9 empty viewport, no composer-card border, fill-only compact controls, one neutral outer shell, and a quieter reference/prompt area.

## Required fidelity surfaces

- Typography: system typography and the existing hierarchy are preserved. Prompt/body text remains regular and fully readable; no new truncation or bold body copy is introduced.
- Spacing and layout rhythm: the output stage leads, reference thumbnails and prompt controls sit directly in the node body, and model/ratio/action controls stay in one footer. Removing the inner composer shell materially reduces visual nesting without changing hit regions.
- Colors and visual tokens: neutral macOS materials remain. Accent blue is reserved for selection, active reference-drop feedback, and the primary action; the resting generator outline is now neutral.
- Image quality and assets: the reference strip uses the real project image. A generated result is loaded from the project asset and shown with `scaledToFit`, so its native aspect ratio is preserved without cropping.
- Copy and content: existing task-specific labels remain concise (`提示词`, model short name, ratio, `生成图片`). The empty viewport still explains its purpose.

## Comparison history

### Iteration 1

- [P2] The output viewport followed the node's selected generation ratio, so an existing 1:1 node still presented a square blank canvas instead of the requested default 16:9 workspace.
- [P2] The generator showed four visible levels of enclosure: node shell, composer shell, media viewport, and outlined controls.
- Fixes: decoupled the empty-stage ratio from the generation parameter and set it to 16:9; removed the composer background/border; removed secondary control strokes; reduced node/media shadows; changed the resting generator outline from accent blue to a neutral border.
- Post-fix evidence: `artifacts/design-qa/generator-simplified-final.jpeg` and `artifacts/design-qa/generator-simplification-final-comparison.png`.

### Iteration 2

- [P3] The generator-level shadow still visually lifted the internal image viewport and made the frame feel heavier than the new flat hierarchy required.
- Fix: removed the generator shadow entirely while preserving its neutral outline and selection/drop-target states.
- Post-fix evidence: the updated `artifacts/design-qa/generator-simplified-final.jpeg` shows a flat image viewport with no cast shadow.

### Iteration 3

No actionable P0, P1, or P2 findings remain. The generated-result state could not be invoked visually because Gemini credentials are not configured in this draft, but the implementation path is deterministic: it selects the newest successful still-image output that still exists, reads `Asset.pixelSize`, and fits the real image at that aspect ratio. Unit and regression tests cover the new 16:9 default and the existing image placement behavior.

## Follow-up polish

- [P3] When a real video-generation action is added, reuse this single-shell composer and supply a video-specific media stage instead of introducing another settings-card hierarchy.

final result: passed

## Generated-output handle fixed to the generator edge

- Source annotation: `artifacts/design-qa/generator-handle-node-edge-source.png`.
- Selected runtime evidence: `artifacts/design-qa/generator-handle-node-edge-selected.png`.
- Deselected runtime evidence: `artifacts/design-qa/generator-handle-node-edge-deselected.png`.
- Comparison: `artifacts/design-qa/generator-handle-node-edge-comparison.png`.
- The generated-output plus is now anchored to the generator body's outside-right edge, independent of whether the displayed result is wide, square, or portrait.
- The output ratio only controls the handle's vertical position, which remains aligned to the visible image midpoint.
- The visible 18-point control has a 14-point gap from the node edge. Its complete 26-point circular hit target is contained by the shell's dedicated 36-point right gutter.
- While the node is selected or actively supplying a drag, the reference line terminates at the plus center. When the contextual control is hidden, the persistent line returns to the generator's right border at the same vertical coordinate.
- This leaves image aspect-fit behavior unchanged and removes the impression that a portrait result owns an in-card connection button.

Validation: runtime selected/deselected visual checks passed at 51% canvas zoom; wide/square/portrait policy assertions passed; `swift test` passed 255 tests with 0 failures; `git diff --check` passed; rebuilt app is open.

final result: passed

## Generated-output reference-line anchor state

- Source visual truth: `artifacts/design-qa/generator-line-anchor-source.png` (586 × 874 px annotated close-up).
- Deselected implementation: `artifacts/design-qa/generator-line-anchor-deselected.png` (1224 × 768 px app window at 51% canvas zoom).
- Selected implementation: `artifacts/design-qa/generator-line-anchor-selected.png` (1224 × 768 px app window at 51% canvas zoom).
- Combined comparison input: `artifacts/design-qa/generator-line-anchor-comparison.png` (1280 × 640 px; both inputs aspect-fit into equal panels).
- State: three chained image-generation nodes with persisted generated-output reference connections.

**Finding and correction**

- [Resolved P1] After the contextual output handle was hidden on deselection, the persisted line still ended at the former handle center and appeared detached from the node. The line now uses the visible image's right-edge anchor while the source node is idle.
- When the source generator is selected, or while it is actively being dragged as a reference, the same line extends to the visible “＋” center. Button visibility and line geometry therefore use the same state rule.
- The anchor now derives from the currently displayed output asset rather than the originally bound asset's dimensions, so switching between outputs with different aspect ratios keeps the line attached to the visible preview.

**Required fidelity surfaces**

- Typography, colors, image rendering, and copy: unchanged.
- Spacing/layout: the idle line meets the visible image edge; the selected-state line meets the handle center without changing node or shelf geometry.
- Interaction: runtime checks covered deselected and selected states across a three-node chain; no disconnected endpoint remained.

Validation: runtime selected/deselected checks passed; `swift test` passed 255 tests with 0 failures; `git diff --check` passed.

final result: passed

## Generated-output handle selection visibility

- Source visual truth: `artifacts/design-qa/generator-handle-selection-gate-source.png` (1422 × 1060 px annotated close-up).
- Deselected implementation: `artifacts/design-qa/generator-handle-selection-gate-implementation.png` (1224 × 768 px app window at 100% canvas zoom).
- Selected implementation: `artifacts/design-qa/generator-handle-selection-gate-selected.png` (1224 × 768 px app window at 100% canvas zoom).
- Combined comparison input: `artifacts/design-qa/generator-handle-selection-gate-comparison.png` (1280 × 640 px; both inputs aspect-fit into equal panels).
- State: an existing image-generation node with retained outputs; comparison covers both selected and deselected node states.

**Finding and correction**

- [Resolved P2] The generated-output reference handle was shown whenever an output existed, leaving permanent blue chrome on idle nodes. It is now rendered only while that generator node belongs to the current canvas selection. During an already-active reference drag it remains mounted until mouse-up so the gesture cannot be interrupted by a transient selection update.
- Runtime accessibility evidence confirms `图片参考输出` is absent after clicking canvas whitespace and present after selecting the generator node.
- Multi-selection follows the same rule: every selected generator retains its own contextual output handle rather than arbitrarily limiting the affordance to the primary selection.

**Required fidelity surfaces**

- Typography: unchanged.
- Spacing/layout: handle geometry, gap, hit area, and connection anchor are unchanged; only state visibility changed.
- Colors/tokens: the selected-state accent-blue circle and white plus are unchanged.
- Image quality: generated previews and historical thumbnails are unchanged.
- Copy/content: no new persistent label or helper text was introduced.

Validation: runtime selected/deselected checks passed; `swift test` passed 255 tests with 0 failures; `git diff --check` passed.

final result: passed

## Generated-output handle shell correction and self-reference guard

- Source visual truth: `artifacts/design-qa/generator-handle-shell-self-guard-source.png` (1306 × 1306 px annotation).
- Runtime evidence: `artifacts/design-qa/generator-handle-shell-self-guard-implementation.jpg` (1224 × 768 px app window at 64% canvas zoom).
- Combined comparison input: `artifacts/design-qa/generator-handle-shell-self-guard-comparison.jpg` (1280 × 640 px, source and implementation aspect-fit into equal panels).
- State: an existing generator with twelve retained outputs, its selected result visible in the main image stage, the generated-output reference handle visible, and one existing external reference connection.

**Findings and correction**

- [Resolved P1] The previous handle was still an overflow overlay owned by the generated image view. SwiftUI could draw it outside the image bounds while exposing only a narrow, displaced portion to hit testing.
- The handle is now a sibling in the generator's real shell layout. Its visible blue circle, circular hit area, accessibility element, and drag-line origin share the exact same policy-derived center.
- The hit area is a compact 26-point world-space circle around the 18-point control, rather than a large rectangular region intruding over the image. A coordinate drag from the visible circle's outer edge was recognized at 64% zoom.
- The persistent reference line for embedded generator outputs now starts from this same visible control center rather than the underlying image edge.
- [Resolved P1] A generator could previously accept one of its own outputs as a reference. The drag target now excludes its source generator, the session binding API rejects the write, and generation validates legacy bindings before any provider request.
- The self-reference rule also covers source-material aliases and legacy outputs whose `sourceGenerationID` is absent but whose Asset ID remains in the originating generation record.

**Required fidelity surfaces**

- Typography: unchanged.
- Spacing/layout: the blue control remains directly outside the selected generated image midpoint; the interaction circle is now centered on what is drawn.
- Colors/tokens: accent blue and the white plus remain unchanged.
- Image quality: the generated image, crop, aspect fit, and historical thumbnails are unchanged.
- Copy/content: self-drop produces the explicit status `生成结果不能作为同一节点自己的参考`.

**Interaction evidence**

- Dragging from the center of the visible handle onto its own generator was rejected with the self-reference status and created no binding.
- Dragging from the visible circle's outer edge onto canvas whitespace was recognized and ended with the normal invalid-target status, confirming the trigger area is centered and usable beyond the glyph itself.
- The accessibility tree exposes one `图片参考输出` element at the generated image edge.

Validation: rebuilt app launched successfully; `swift test` passed 255 tests with 0 failures; `git diff --check` passed.

final result: passed

## Generator prompt baseline and output-handle reliability

- The editable generator prompt now reserves three text lines by default while continuing to grow for longer content.
- The canonical generator height increased from 390 to 426 world points so the larger editor does not compress the reference row or footer.
- The generated-output reference handle is positioned 12 world points beyond the visible image edge, with a 56-point transparent hover/drag corridor that overlaps the image and extends into a dedicated right-side shell gutter.
- Reference dragging now claims the pointer immediately and always draws from the visible plus-circle center rather than from an arbitrary press position inside the transparent hit target.
- The generator card's old body-only content shape no longer clips the outboard handle's interaction region.

Validation: runtime visual check passed at 80% canvas zoom; dragging the generated-output handle to canvas whitespace left the generator fixed and completed without losing the gesture; `swift test` passed 245 tests with 0 failures; `git diff --check` passed.

final result: passed

## Generator top-inset regression correction

- Regression reference: `artifacts/design-qa/generator-top-inset-regression.png`.
- Runtime verification: `artifacts/design-qa/generator-top-inset-correction-final.png`; focused crop: `artifacts/design-qa/generator-top-inset-correction-final-crop.png`.
- Narrow legacy generator nodes can have less content width than the new 440-point default. Their wide image therefore fits by width and leaves unused vertical space inside the fixed media stage.
- The image is now pinned to the stage's shared top inset instead of vertically centering that unused space. Left/right centering and aspect-fit behavior remain unchanged.
- The shared reference-line geometry uses the same top-aligned media frame, keeping the output connector attached to the visible image midpoint.
- A narrow-node regression test locks the 8-point top inset and the fitted 364 × 204.75 media frame.

Validation: runtime visual check passed at 64% canvas zoom; `swift test` passed 245 tests with 0 failures; `git diff --check` passed.

final result: passed

## Dynamic generator media-stage height

- Source annotation: `artifacts/design-qa/generator-dynamic-stage-annotation.png`.
- Runtime verification: `artifacts/design-qa/generator-dynamic-stage-final.png`.
- The generator media stage now derives its actual height from the current node width and selected image ratio, capped by the existing portrait/square maximum.
- Wide images no longer leave unused fixed-stage space between the image and the reference/prompt content.
- The generator's fitted baseline height subtracts the same stage-height delta, so the empty area is removed rather than merely moved elsewhere in the node.
- Switching output thumbnails continues to preserve each image's aspect ratio and automatically refits the node height.
- The shared reference anchor uses the same dynamic media frame, keeping connection lines attached to the displayed image.

Validation: runtime visual check passed at 64% canvas zoom; `swift test` passed 245 tests with 0 failures; `git diff --check` passed.

final result: passed

## Unified generation settings control

- Source references: `artifacts/design-qa/generator-settings-before.png` and `artifacts/design-qa/generator-settings-reference.png`.
- Runtime verification: `artifacts/design-qa/generator-merged-settings-control.png` and `artifacts/design-qa/generator-merged-settings-popover.png`.
- The former model, aspect-ratio, and output-count pills are replaced by one compact settings control. Its first line identifies the model; the second line summarizes ratio and output count.
- The primary generation action remains a separate blue button, preserving a clear distinction between configuration and execution.
- Clicking the unified control opens one grouped popover with three sections: model, image ratio, and generation count. All existing compatibility checks and 1–4 output limits remain intact.
- The control is fill-only, uses no extra enclosing border, and fits the compact generator footer without reintroducing nested cards.
- Accessibility exposes a single descriptive settings button containing the current model, ratio, and count.

Validation: runtime visual and interaction check passed at 64% canvas zoom; the grouped popover exposed all three setting sections; `swift test` passed 244 tests with 0 failures; `git diff --check` passed.

final result: passed

## Generated-output reference connection

- Runtime evidence: `artifacts/design-qa/generator-output-reference-handle.png`
- A generator with a successful output now exposes the same blue plus connection affordance at the visible generated image's outside-right midpoint.
- The affordance appears while the image is hovered and remains visible while its generator is selected, so it is discoverable without adding permanent chrome to every idle node.
- Dragging starts the existing reference-connection curve and uses the selected output Asset ID. Dropping on another compatible generation node reuses the existing model capability, duplicate, and reference-limit validation.
- Persisted reference lines now fall back to the source generator's fitted media viewport when a generated Asset has no independent canvas image node. The shared geometry policy keeps the line attached to the actual image edge for wide, square, and portrait results.
- The output remains a generated result rather than being duplicated or converted into a normal source asset, so this interaction adds no image bytes to the project.
- Accessibility exposes the selected output's `图片参考输出` control with a reference-drag hint.

Validation: selected-state visual check passed at 64% canvas zoom; `swift test` passed 244 tests with 0 failures; `git diff --check` passed.

final result: passed

## Square result rail interaction correction

- Verified screenshot: `artifacts/design-qa/generator-square-scroll-implementation.png`
- Runtime state: 4 historical generation batches, 12 retained images.
- Thumbnails are now 54 × 54 square previews in one horizontal row above the generator body.
- The rail and generator body are real sibling views inside one derived shell. This replaces the earlier negative-offset overlay that could be drawn outside the node while remaining outside its hit-test area.
- A coordinate-level mouse click on an older thumbnail changed both the selected blue outline and the generator's main image preview.
- The horizontal result rail was moved to both ends through its real scroll accessibility actions, confirming that all 12 historical images remain browsable while the generator body and canvas position stay fixed.
- Horizontal precise scrolling over the rail is routed to the rail; vertical scrolling and gestures outside it remain owned by the infinite canvas.
- The shell only adds one fixed-height row to culling. Historical outputs remain append-only and do not increase the persisted node frame or recreate result nodes/groups.

Validation: `swift test` passed 242 tests; `git diff --check` passed.

### Result rail gesture safety zone

- The rail now publishes a safety region extending 10 view points beyond its visible bounds on every side.
- Any precise trackpad gesture that begins inside this region is owned by the result rail for the entire gesture sequence, including slightly diagonal first deltas.
- The canvas no longer receives that gesture midway through, so horizontal browsing cannot unexpectedly pan the board.
- Event ownership is resolved from the scroll event's actual local position rather than a potentially stale global mouse position.
- Outside the safety region, scrolling continues to pan the infinite canvas normally.

## Compact node spacing pass

- Source reference: `artifacts/design-qa/generator-spacing-source.png`
- Runtime verification: `artifacts/design-qa/generator-compact-spacing-implementation.jpg`
- The generator shell inset is reduced from 14 to 8 world points, and its inner composer inset is reduced from 12 to 8. The main image now sits materially closer to the node edge without touching it.
- Vertical section spacing is reduced from 10 to 6–7 points. The reference strip, editable prompt, and footer controls now read as one compact composition rather than widely separated bands.
- Prompt-module and note nodes use 10-point content padding instead of 14, with 12-point shells, so the same spacing discipline is applied across node families rather than only to image generation.
- The standard generator height is reduced from 560 to 390. Existing standard/oversized generator frames are fitted back to their content because manual node resizing is disabled; a long prompt still increases the required height after two lines and remains fully visible.
- No interaction geometry was reintroduced: nodes remain non-resizable, the external result rail remains independently scrollable, and reference/input anchors continue to use the shared layout policy.

Validation: visual comparison passed at 64% canvas zoom; `swift test` passed 242 tests with 0 failures; `git diff --check` passed.

final result: passed

## Annotated generator spacing and action alignment

- Source annotations: `artifacts/design-qa/generator-spacing-annotation.png` and `artifacts/design-qa/generator-footer-alignment-annotation.png`.
- Runtime capture: `artifacts/design-qa/generator-annotated-spacing-final.png`; focused crop: `artifacts/design-qa/generator-annotated-spacing-final-crop.png`.
- Side-by-side QA input: `artifacts/design-qa/generator-annotated-spacing-comparison.png`.
- The 16:9 media stage now derives its height from the default 440-point node width and shared 8-point inset. The displayed image therefore uses the same 8-point top, left, and right spacing instead of being height-limited with extra horizontal whitespace.
- Square and portrait outputs remain aspect-fit and centered; their native proportions are not cropped to force equal whitespace.
- The primary generate/cancel action now uses a dedicated 38 × 38-point world-space control, matching the unified settings row height exactly.
- The arrow/stop symbol is centered by an explicit square frame rather than inheriting the previous text-button baseline and 28-point height.
- Both compact action states retain explicit accessibility labels and continue to scale with the canvas.

Validation: focused runtime capture passed at 64% canvas zoom; `swift test` passed 244 tests with 0 failures; `git diff --check` passed.

final result: passed

## Generated-output handle hit target and command-wheel zoom

- Source visual truth: `artifacts/design-qa/generator-handle-hitbox-annotation.png` (1306 × 1306 px).
- Implementation evidence: `artifacts/design-qa/generator-handle-hitbox-implementation.jpg` (1224 × 768 px app window at 100% canvas zoom).
- Combined comparison input: `artifacts/design-qa/generator-handle-hitbox-comparison.png` (1300 × 650 px; both inputs aspect-fit into 650 × 650 panels at 1× density).
- State: existing project with a selected image-generation node, twelve retained historical outputs, a visible generated-image reference handle, and both side panels hidden for the focused canvas check.
- The source is a close annotation of the erroneous trigger area while the implementation evidence is a full-window runtime capture, so absolute component scale is intentionally not treated as a fidelity measurement. The focused comparison verifies placement and relative hit-area intent.

**Findings and correction**

- [Resolved P1] The visible plus had been aligned to the trailing edge of a 56-point transparent hit frame. Its apparent center therefore disagreed with the gesture origin, and most of the hot region intruded over the generated image.
- The plus is now centered inside its real interaction frame, and reference lines start from that same center.
- The generated-output handle uses a 40-point hit target with a 10-point visible gap from the image. At 100% zoom its hot region overlaps the image edge by only one point for hover continuity and remains within the generator shell's reserved right gutter.
- The blue circle and plus remain world-scaled with the canvas; only the invisible interaction geometry was corrected.
- `Cmd + mouse wheel` now takes precedence over result-rail scrolling and canvas panning, applies continuous exponential zoom around the event location, and continues to use the existing 20%–400% viewport limits.

**Required fidelity surfaces**

- Typography: unchanged; no text or optical-weight drift introduced.
- Spacing/layout: the visible handle sits immediately outside the generated image midpoint with a compact, intentional gap; the node and result rail retain their existing geometry.
- Colors/tokens: the existing accent-blue circle and white plus are unchanged.
- Image quality: the generated image remains aspect-fit and unmodified.
- Copy/content: unchanged.

**Interaction evidence**

- Selecting the generator exposed the `图片参考输出` accessibility control at the generated image edge.
- A coordinate drag initiated from the visible handle and released on canvas whitespace without moving the generator or leaving a stuck connection draft.
- The wheel-zoom conversion is covered for direction, reciprocal behavior, precise/non-precise sensitivity, zero/non-finite input, and extreme-delta clamping.

Validation: the rebuilt app launched successfully; `swift test` passed 249 tests with 0 failures; `git diff --check` passed.

final result: passed

## Latest verification — shell-owned reference handle and self-link exclusion

- Source: `artifacts/design-qa/generator-handle-shell-self-guard-source.png`.
- Implementation: `artifacts/design-qa/generator-handle-shell-self-guard-implementation.jpg`.
- Combined QA input: `artifacts/design-qa/generator-handle-shell-self-guard-comparison.jpg`.
- The earlier 40-point overflow overlay is superseded. The current implementation uses a shell-owned, circular 26-point world-space hit region centered on the visible 18-point blue control.
- The visual center, pointer target, transient drag curve, and persisted connection anchor now use the same `GeneratorNodeLayoutPolicy.outputReferenceHandleCenter` geometry.
- Runtime edge-drag verification at 64% zoom confirmed that the visible circle's outer edge starts the reference gesture.
- Runtime self-drop verification confirmed that a generator rejects its own selected output with `生成结果不能作为同一节点自己的参考` and does not create a binding.
- Core tests also cover source aliases, legacy output records without `sourceGenerationID`, cross-generator references, and ordinary imported media.

Validation: rebuilt app launched successfully; `swift test` passed 255 tests with 0 failures; `git diff --check` passed.

final result: passed
