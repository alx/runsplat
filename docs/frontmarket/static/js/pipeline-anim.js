(function () {
  // Animate pipeline steps and arrows when they enter the viewport.
  const steps = document.querySelectorAll('.pipe-step');
  const arrows = document.querySelectorAll('.pipe-arrow');

  if (!steps.length) return;

  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        const el = entry.target;
        const idx = parseInt(el.dataset.step ?? el.dataset.arrow ?? '0', 10);
        setTimeout(() => el.classList.add('visible'), idx * 120);
        observer.unobserve(el);
      });
    },
    { threshold: 0.2 }
  );

  steps.forEach((el) => observer.observe(el));
  arrows.forEach((el) => observer.observe(el));

  // Code tab switcher
  document.querySelectorAll('.code-tab').forEach((tab) => {
    tab.addEventListener('click', () => {
      const target = tab.dataset.target;
      document.querySelectorAll('.code-tab').forEach((t) => t.classList.remove('active'));
      document.querySelectorAll('.code-block').forEach((b) => b.classList.remove('active'));
      tab.classList.add('active');
      document.getElementById(target)?.classList.add('active');
    });
  });
})();
