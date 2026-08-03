### Task 7: Library hover preview

**Files:**
- Modify: `App/ARShader/LibraryPanelView.swift` — hover shows the still
- Test: `App/ARShaderTests/ThumbnailServiceTests.swift` — interactive-priority cancellation

**Interfaces:**
- Consumes: `ThumbnailService.thumbnail(for:priority:)` at `.interactive`, and `cancelInteractive()`.
- Produces: nothing downstream.

- [ ] **Step 1: Write the failing test** — a hover sweep must not leave queued work behind:

```swift
    /// Hover is superseded constantly as the pointer moves; a thumbnail for a row the pointer has
    /// left is wasted work. This is the OPPOSITE of the bank's requirement, which is why priority
    /// is a parameter rather than a policy baked into the service.
    func testAnInteractiveRequestSupersedesItsPredecessor() async throws {
        let service = ThumbnailService(cacheDirectory: try temporaryCacheDirectory())
        async let first = service.thumbnail(for: fixtureURL("slow"), priority: .interactive)
        await service.cancelInteractive()
        let result = await first
        XCTAssertEqual(result, .unavailable,
                       "a cancelled interactive request resolves as unavailable, never hangs")
    }

    /// And the guard that matters: cancelling hover work must not touch the bank's queue.
    func testCancellingInteractiveWorkLeavesBatchWorkAlone() async throws {
        let service = ThumbnailService(cacheDirectory: try temporaryCacheDirectory())
        async let batch = service.thumbnail(for: fixtureURL("solid_red"), priority: .batch)
        await service.cancelInteractive()
        if case .unavailable = await batch {
            XCTFail("Cancelling hover work must never drop a queued bank thumbnail — that leaves "
                    + "permanently blank cells only a resize or relaunch would fill.")
        }
    }
```

- [ ] **Step 2: Run — expect FAIL** until the hover path exists and the priorities are honoured.

- [ ] **Step 3: Add the hover preview.** `.onHover` on each library row requests at `.interactive` and shows the still in a fixed-size well at the panel's foot — not a floating popover, which would sit over the rows the operator is scanning. On hover-exit of the whole list, call `cancelInteractive()`.

- [ ] **Step 4: Run the suite. Mutation-prove:** make `cancelInteractive()` cancel everything. Expected: `testCancellingInteractiveWorkLeavesBatchWorkAlone` FAILS. Revert.

- [ ] **Step 5: Commit**

```bash
git add App/ARShader/LibraryPanelView.swift App/ARShaderTests/ThumbnailServiceTests.swift
git commit -m "feat(3c): library hover shows the shader's still"
```

---

