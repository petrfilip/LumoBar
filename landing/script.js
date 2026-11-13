const header = document.querySelector("[data-header]");
const copyButton = document.querySelector("[data-copy-command]");
const installCommand = document.querySelector("[data-install-command]");

const setHeaderState = () => {
  if (!header) return;
  header.toggleAttribute("data-scrolled", window.scrollY > 12);
};

setHeaderState();
window.addEventListener("scroll", setHeaderState, { passive: true });

copyButton?.addEventListener("click", async () => {
  if (!installCommand?.textContent) return;

  const original = copyButton.textContent;

  try {
    await navigator.clipboard.writeText(installCommand.textContent.trim());
    copyButton.textContent = "Copied!";
    window.setTimeout(() => {
      copyButton.textContent = original;
    }, 1800);
  } catch {
    copyButton.textContent = "Select";
  }
});
