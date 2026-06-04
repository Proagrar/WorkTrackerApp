import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';
import { SUPABASE_URL, SUPABASE_ANON_KEY } from './config.js';

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// ── Redirect if already authenticated ─────────────────────────
supabase.auth.getSession().then(({ data: { session } }) => {
  if (session) window.location.replace('app.html');
});

// ── DOM refs ───────────────────────────────────────────────────
const form      = document.getElementById('loginForm');
const emailEl   = document.getElementById('email');
const passwordEl= document.getElementById('password');
const errorEl   = document.getElementById('loginError');
const loginBtn  = document.getElementById('loginBtn');

// ── Submit ─────────────────────────────────────────────────────
form.addEventListener('submit', async (e) => {
  e.preventDefault();

  const email    = emailEl.value.trim();
  const password = passwordEl.value;

  if (!email || !password) {
    showError('Vnesite e-pošto in geslo.');
    return;
  }

  setLoading(true);
  hideError();

  const { error } = await supabase.auth.signInWithPassword({ email, password });

  if (error) {
    setLoading(false);
    showError(error.message === 'Invalid login credentials'
      ? 'Napačna e-pošta ali geslo.'
      : error.message);
    passwordEl.value = '';
    passwordEl.focus();
    return;
  }

  window.location.replace('app.html');
});

function showError(msg) {
  errorEl.textContent = msg;
  errorEl.hidden = false;
}

function hideError() {
  errorEl.hidden = true;
}

function setLoading(on) {
  loginBtn.disabled = on;
  loginBtn.querySelector('.btn-label').hidden = on;
  loginBtn.querySelector('.btn-spinner').hidden = !on;
}
