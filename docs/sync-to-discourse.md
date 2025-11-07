# Synchronizing Documentation with Discourse

## Publishing to Discourse (Git → Discourse)

### Step 1: Prepare the Content
```bash
# View the documentation
cat BENUTZERHANDBUCH.md

# Or copy to clipboard (macOS)
pbcopy < BENUTZERHANDBUCH.md
```

### Step 2: Create/Update Post in Discourse
1. Navigate to your Discourse forum
2. Create a new post or edit existing documentation post
3. Paste the markdown content (Cmd+V / Ctrl+V)
4. Discourse will show placeholder icons for images

### Step 3: Upload Images
1. Open Finder and navigate to `docs/images/`
2. For each placeholder in Discourse:
   - Drag and drop the corresponding image file
   - Discourse uploads automatically and replaces the local path with CDN URL
3. Preview to verify all images loaded correctly
4. Publish the post

### Step 4: Save Post URL (optional)
Store the Discourse post URL in this file for future reference:

**Documentation Post URL**: [Add URL here after first publish]

---

## Exporting from Discourse (Discourse → Git)

If you need to pull updates made in Discourse back to git:

### Step 1: Get Raw Markdown
Visit: `https://your-forum.com/raw/TOPIC_ID` (replace with actual topic ID)

### Step 2: Download Images
For each image in the raw markdown:
1. Find URLs like `![...](https://your-forum.com/uploads/...)`
2. Download each image manually
3. Save to `docs/images/` with proper naming (01-15)
4. Replace Discourse CDN URLs with local paths in markdown

### Step 3: Update Git Repository
```bash
# Save the updated markdown
vim BENUTZERHANDBUCH.md

# Add and commit changes
git add BENUTZERHANDBUCH.md docs/images/*.png
git commit -m "Update documentation from Discourse"
```

---

## Recommended Workflow

**Git as source of truth** (recommended):
- Edit markdown files in git
- Take/save screenshots locally in `docs/images/`
- Commit everything together
- Publish to Discourse manually when ready

**Benefits**:
- Version control for both text and images
- Work offline
- Easy to review changes in PRs
- Single source of truth

**Discourse as display only**:
- Use Discourse purely for nice viewing
- Don't edit directly in Discourse
- Re-publish from git when documentation changes

---

## Tips

### Taking Consistent Screenshots
```bash
# Use consistent window size for all screenshots
# macOS: Use Cmd+Shift+4, then Space to capture window
# Make sure browser zoom is at 100%
```

### Image Optimization (optional)
```bash
# Optimize PNG file sizes (requires pngcrush)
brew install pngcrush
pngcrush -brute input.png output.png

# Or use ImageOptim.app on macOS
```

### Batch Upload to Discourse
Unfortunately, Discourse doesn't have a bulk image upload API for public posts. Images must be uploaded one by one through the UI. Consider using the browser console to automate if you have many images:

```javascript
// This is an advanced technique - use with caution
// Upload images programmatically via Discourse API
// See: https://docs.discourse.org/#tag/Uploads
```
