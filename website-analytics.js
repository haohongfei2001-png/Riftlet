(() => {
  'use strict';
  // The live website remains tracker-free until its Umami website ID is configured.
  const meta = document.querySelector('meta[name="riftlet-umami-website-id"]');
  const websiteId = meta ? (meta.getAttribute('content') || '').trim() : '';
  if (!/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(websiteId)) return;
  if (window.location.protocol !== 'https:' ||
      !['riftlet.com', 'www.riftlet.com'].includes(window.location.hostname)) return;
  if (navigator.doNotTrack === '1' || window.doNotTrack === '1' ||
      navigator.globalPrivacyControl === true) return;
  try {
    if (window.localStorage.getItem('umami.disabled') === '1') return;
  } catch (_) { /* Storage can be unavailable; do not persist tracking IDs. */ }
  if (document.getElementById('riftlet-umami-tracker')) return;
  // Dynamic scripts may run without document.currentScript; give Umami an explicit host.
  window.umamiConfig = { websiteId, hostUrl: 'https://cloud.umami.is' };
  const script = document.createElement('script');
  script.id = 'riftlet-umami-tracker';
  script.src = 'https://cloud.umami.is/script.js';
  script.async = true;
  script.referrerPolicy = 'strict-origin-when-cross-origin';
  script.setAttribute('data-website-id', websiteId);
  script.setAttribute('data-domains', 'riftlet.com,www.riftlet.com');
  script.setAttribute('data-do-not-track', 'true');
  script.setAttribute('data-exclude-hash', 'true');
  document.head.appendChild(script);
})();
