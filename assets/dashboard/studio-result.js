/* Generated media is reference data. This viewer cannot approve or publish it. */
(async () => {
  const root = document.getElementById('studio-result');
  const status = document.getElementById('result-status');
  const host = document.getElementById('result-media');
  const resource = root.dataset.resource;
  const kind = root.dataset.kind;
  const visual = /^\/api\/v1\/visual\/image\/visual_project_[a-f0-9]{16}\/visual_candidate_[a-f0-9]{16}$/;
  const audio = /^\/api\/v1\/music\/audio\/music_[a-f0-9]{16}\/candidate_[a-f0-9]{16}\/(mp3|flac)$/;
  if (!((kind === 'image' && visual.test(resource)) || (kind === 'audio' && audio.test(resource)))) {
    status.textContent = 'This review address is invalid. No media was requested.';
    return;
  }
  try {
    const response = await fetch('/auth/v1/session', {credentials: 'same-origin', cache: 'no-store'});
    const auth = await response.json();
    if (!response.ok || auth.authenticated !== true || auth.password_change_required) {
      status.textContent = 'Sign in to the Soul dashboard, then return here and refresh to review this draft.';
      return;
    }
    const media = document.createElement(kind === 'image' ? 'img' : 'audio');
    if (kind === 'image') {
      media.alt = 'Generated Studio image awaiting human review';
      media.onload = () => { status.textContent = 'Image ready for review.'; };
    } else {
      media.controls = true;
      media.preload = 'metadata';
      media.onloadedmetadata = () => { status.textContent = `Audio ready for listening review — ${media.duration.toFixed(1)} seconds.`; };
    }
    media.onerror = () => { status.textContent = 'Media could not be opened. Check your dashboard session and the retained Studio result; no generation was retried.'; };
    status.textContent = 'Loading your authenticated Studio result…';
    media.src = resource;
    host.append(media);
  } catch (_) {
    status.textContent = 'The dashboard session could not be checked. No media was requested.';
  }
})();
