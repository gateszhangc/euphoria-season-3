import "./styles.css";

const root = document.documentElement;
const header = document.querySelector("[data-header]");
const sections = [...document.querySelectorAll("[data-section]")];
const navLinks = [...document.querySelectorAll("[data-nav-link]")];

const setHeaderState = () => {
  header?.toggleAttribute("data-scrolled", window.scrollY > 10);
};

const setActiveLink = (id) => {
  for (const link of navLinks) {
    const isActive = link.getAttribute("href") === `#${id}`;
    link.toggleAttribute("data-active", isActive);
  }
};

const observer = new IntersectionObserver(
  (entries) => {
    const visible = entries
      .filter((entry) => entry.isIntersecting)
      .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];

    if (visible?.target?.id) {
      setActiveLink(visible.target.id);
    }
  },
  {
    threshold: [0.2, 0.45, 0.7],
    rootMargin: "-20% 0px -45% 0px"
  }
);

for (const section of sections) {
  observer.observe(section);
}

window.addEventListener("scroll", setHeaderState, { passive: true });
window.addEventListener(
  "pointermove",
  (event) => {
    root.style.setProperty("--pointer-x", `${(event.clientX / window.innerWidth) * 100}%`);
    root.style.setProperty("--pointer-y", `${(event.clientY / window.innerHeight) * 100}%`);
  },
  { passive: true }
);

setHeaderState();
setActiveLink("what-we-know");
