import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';
import { SUPABASE_URL, SUPABASE_ANON_KEY } from './config.js';

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

const errorEl = document.getElementById('loginError');

// Redirect if already authenticated
supabase.auth.getSession().then(({ data: { session } }) => {
  if (session) window.location.replace('app.html');
});

document.getElementById('googleBtn').addEventListener('click', () => signInWith('google'));
document.getElementById('facebookBtn').addEventListener('click', () => signInWith('facebook'));

async function signInWith(provider) {
  errorEl.hidden = true;
  const { error } = await supabase.auth.signInWithOAuth({
    provider,
    options: { redirectTo: new URL('app.html', window.location.href).href },
  });
  if (error) {
    errorEl.textContent = 'Prijava ni uspela. Poskusite znova.';
    errorEl.hidden = false;
  }
}

const loginForm = document.getElementById('loginForm');
const loginBtn  = document.getElementById('loginBtn');

loginForm.addEventListener('submit', async e => {
  e.preventDefault();
  const email    = document.getElementById('email').value.trim();
  const password = document.getElementById('password').value;
  if (!email || !password) {
    errorEl.textContent = 'Vnesite e-pošto in geslo.';
    errorEl.hidden = false;
    return;
  }
  errorEl.hidden = true;
  loginBtn.disabled = true;
  loginBtn.querySelector('.btn-label').hidden = true;
  loginBtn.querySelector('.btn-spinner').hidden = false;

  const { error } = await supabase.auth.signInWithPassword({ email, password });

  loginBtn.disabled = false;
  loginBtn.querySelector('.btn-label').hidden = false;
  loginBtn.querySelector('.btn-spinner').hidden = true;

  if (error) {
    errorEl.textContent = error.message === 'Invalid login credentials'
      ? 'Napačna e-pošta ali geslo.'
      : error.message;
    errorEl.hidden = false;
    document.getElementById('password').value = '';
    return;
  }

  window.location.replace('app.html');
});
