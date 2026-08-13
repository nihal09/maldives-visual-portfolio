/* ============================================================
   NIHAL SINGH — MALDIVES VISUAL PORTFOLIO
   Reveals · word-splitting · parallax · scroll video · rail
   ============================================================ */
(function () {
  "use strict";

  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const noHover = window.matchMedia("(hover: none)").matches;
  if (noHover) document.body.classList.add("no-hover");

  /* ---------- word splitting for typographic reveals ---------- */
  function wordSplit(el) {
    const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
    let i = 0;
    const texts = [];
    while (walker.nextNode()) {
      const node = walker.currentNode;
      if (!node.textContent.trim()) continue;
      texts.push(node);
    }
    texts.forEach(function (node) {
      const frag = document.createDocumentFragment();
      const words = node.textContent.split(/(\s+)/);
      words.forEach(function (w) {
        if (!w) return;
        if (/^\s+$/.test(w)) {
          frag.appendChild(document.createTextNode(" "));
          return;
        }
        const s = document.createElement("span");
        s.className = "w";
        s.style.setProperty("--i", i++);
        s.textContent = w;
        frag.appendChild(s);
        frag.appendChild(document.createTextNode(" "));
      });
      node.parentNode.replaceChild(frag, node);
    });
  }

  document.querySelectorAll('[data-r="lines"], [data-r="words"], [data-split]').forEach(wordSplit);

  /* ---------- scroll reveal ---------- */
  const revealEls = document.querySelectorAll(".reveal, .closing-title");
  if (reduced) {
    revealEls.forEach((el) => el.classList.add("in"));
  } else if ("IntersectionObserver" in window) {
    const io = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) {
            entry.target.classList.add("in");
            io.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.06, rootMargin: "0px 0px 0px 0px" }
    );
    revealEls.forEach((el) => io.observe(el));
    document.querySelectorAll("#contact .reveal").forEach((el) => io.observe(el));
  } else {
    revealEls.forEach((el) => el.classList.add("in"));
  }

  /* scroll-based reveal fallback (works even if IntersectionObserver
     misbehaves in webviews/embedders) */
  const allReveals = Array.prototype.slice.call(revealEls);
  function checkVisibility() {
    if (reduced) return;
    const vh = window.innerHeight;
    allReveals.forEach(function (el) {
      if (el.classList.contains("in")) return;
      const r = el.getBoundingClientRect();
      if (r.top < vh * 0.92 && r.bottom > 0) el.classList.add("in");
    });
  }

  /* ---------- parallax (fine pointers only, cheap) ---------- */
  const finePointer = window.matchMedia("(pointer: fine)").matches;
  const parallaxEls = Array.prototype.slice.call(document.querySelectorAll("[data-parallax]"));
  let ticking = false;

  function parallax() {
    ticking = false;
    if (reduced || !finePointer) return;
    const vh = window.innerHeight;
    parallaxEls.forEach(function (el) {
      if (el.closest("body") === null) return;
      const r = el.getBoundingClientRect();
      if (r.bottom < -150 || r.top > vh + 150) return;
      const factor = parseFloat(el.dataset.parallax) || 0.04;
      const center = r.top + r.height / 2 - vh / 2;
      const maxDev = r.height * 0.14;
      let y = center * -factor;
      y = Math.max(-maxDev, Math.min(maxDev, y));
      el.style.willChange = "transform";
      el.style.transform = "translate3d(0," + y.toFixed(2) + "px,0)";
    });
  }

  function onScroll() {
    if (!ticking) {
      ticking = true;
      requestAnimationFrame(parallax);
    }
    headerState();
    updateRail();
    checkVisibility();
    tourCheck();
  }

  /* ---------- side rail progress ---------- */
  const railNum = document.querySelector(".rail-num");
  const railLine = document.querySelector(".rail-line");
  const sections = Array.prototype.slice.call(document.querySelectorAll("[data-section]"));
  const hero = document.querySelector(".hero");

  function updateRail() {
    if (!railNum) return;
    const doc = document.documentElement;
    const max = doc.scrollHeight - window.innerHeight;
    const p = max > 0 ? window.scrollY / max : 0;
    if (railLine) railLine.style.transform = "scaleY(" + Math.min(1, Math.max(0.001, p)) + ")";

    let current = 1;
    sections.forEach(function (sec, idx) {
      const r = sec.getBoundingClientRect();
      if (r.top <= window.innerHeight * 0.35) current = idx + 1;
    });
    let n = current;
    if (hero && hero.getBoundingClientRect().bottom > 0 && hero.getBoundingClientRect().top < window.innerHeight) {
      n = 1;
    }
    railNum.textContent = String(n).padStart(2, "0");
  }

  /* ---------- scroll-driven video playback ----------
   two-stage: warm up (fetch) one screen ahead, play only when in view.
   villa-tour films are ambient too, but both may play at once; on
   desktop they pause while hovered and resume on leave. */
  const videos = Array.prototype.slice.call(document.querySelectorAll("video"));
  const tourVideos = videos.filter((v) => !!v.closest(".tour-film"));
  const playables = videos.filter(
    (v) => !v.hasAttribute("autoplay") && !v.closest(".tour-film")
  );
  const heroVideo = document.querySelector(".hero-video");

  if ("IntersectionObserver" in window) {
    // warm-up: start fetching the file 1.5 viewports early
    const warmIO = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          const v = entry.target;
          if (entry.isIntersecting) {
            if (v.preload === "none" && !v.getAttribute("data-warmed")) {
              v.setAttribute("data-warmed", "1");
              v.preload = "metadata";
            }
            warmIO.unobserve(v);
          }
        });
      },
      { rootMargin: "150% 0px 150% 0px", threshold: 0 }
    );
    videos.forEach((v) => warmIO.observe(v));

    // ambient playback: play in view, pause out of view, single-player policy
    let active = null;
    const videoIO = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          const v = entry.target;
          if (entry.isIntersecting) {
            const pr = v.play();
            if (pr) pr.catch(function () {});
            if (v !== heroVideo && v !== active) {
              if (active && !active.paused) active.pause();
              active = v;
            }
          } else if (!v.paused) {
            v.pause();
          }
        });
      },
      { threshold: 0.25 }
    );
    playables.forEach((v) => videoIO.observe(v));
    if (heroVideo) videoIO.observe(heroVideo);
  }

  /* tour films: ambient, but both may play at once. driven by the
     scroll handler (deterministic) so the two side-by-side films
     always start together; pause while hovered on desktop. */
  function tourCheck() {
    const vh = window.innerHeight;
    tourVideos.forEach(function (v) {
      if (v.getAttribute("data-hovered") === "1") return;
      const r = v.getBoundingClientRect();
      const inView = r.top < vh * 0.98 && r.bottom > vh * 0.02;
      if (inView) {
        if (v.paused) {
          const pr = v.play();
          if (pr) pr.catch(function () {});
        }
      } else if (!v.paused) {
        v.pause();
      }
    });
  }

  /* pause the tour films while hovered; resume on leave (desktop only) */
  if (!noHover) {
    tourVideos.forEach(function (v) {
      v.addEventListener("mouseenter", function () {
        v.setAttribute("data-hovered", "1");
        if (!v.paused) v.pause();
      });
      v.addEventListener("mouseleave", function () {
        v.removeAttribute("data-hovered");
        const pr = v.play();
        if (pr) pr.catch(function () {});
      });
    });
  }

  /* click-to-mute toggle on ambient section videos */
  playables.forEach(function (v) {
    v.addEventListener("click", function () {
      v.muted = !v.muted;
    });
  });

  /* ---------- header scrolled state ---------- */
  const head = document.querySelector(".site-head");

  function headerState() {
    if (head) head.classList.toggle("scrolled", window.scrollY > 40);
  }

  function rafInit() {
    headerState();
    onScroll();
    checkVisibility();
  }

  window.addEventListener("scroll", onScroll, { passive: true });
  window.addEventListener("resize", onScroll, { passive: true });
  setInterval(function () { checkVisibility(); tourCheck(); }, 650);
  rafInit();

  /* iOS quirk: kickstart muted autoplay on first interaction */
  var touchStarted = false;
  function kickstart() {
    if (touchStarted) return;
    touchStarted = true;
    videos.forEach(function (v) {
      if (v.paused) {
        var pr = v.play();
        if (pr) pr.catch(function () {});
      }
    });
  }
  ["touchstart", "pointerdown", "scroll"].forEach(function (evt) {
    window.addEventListener(evt, kickstart, { passive: true, once: true });
  });
})();