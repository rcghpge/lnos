document.addEventListener('DOMContentLoaded', function () {
  // Find the Honkit header; “buttons” group varies by theme, so fall back to header
  const header = document.querySelector('.book-header');
  if (!header) return;

  // Prefer right-side controls group if present; else, use header root
  const rightSide = header.querySelector('.pull-right') || header;

  // Build the GitHub button
  const a = document.createElement('a');
  a.href = 'https://github.com/uta-lug-nuts/LnOS';   // <- upstream link
  a.target = '_blank';
  a.rel = 'noopener';
  a.className = 'github-header-btn';
  a.title = 'Upstream LnOS on GitHub';
  a.setAttribute('aria-label', 'Upstream LnOS on GitHub');

  // Inline SVG GitHub mark (no external assets needed)
  a.innerHTML = `
    <svg viewBox="0 0 16 16" aria-hidden="true">
      <path d="M8 0C3.58 0 0 3.58 0 8a8 8 0 0 0 5.47 7.59c.4.07.55-.17.55-.38
               0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13
               -.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66
               .07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15
               -.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82a7.62 7.62 0 0 1 2-.27
               c.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82 .44 1.1.16 1.92.08 2.12
               .51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48
               0 1.07-.01 1.93-.01 2.19 0 .21.15.45.55.38A8 8 0 0 0 16 8c0-4.42-3.58-8-8-8z"/>
    </svg>
  `;

  // Set GiHub repository link as the first control on the right
  if (rightSide.firstChild) {
    rightSide.insertBefore(a, rightSide.firstChild);
  } else {
    rightSide.appendChild(a);
  }
});

