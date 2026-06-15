import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';
import { SUPABASE_URL, SUPABASE_ANON_KEY } from './config.js';

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

const errorEl   = document.getElementById('loginError');
const successEl = document.getElementById('loginSuccess');
const loginBtn  = document.getElementById('loginBtn');
const btnLabel  = loginBtn.querySelector('.btn-label');
const toggleLink = document.getElementById('authToggleLink');

const fullNameField       = document.getElementById('fullNameField');
const confirmPasswordField = document.getElementById('confirmPasswordField');
const passwordInput       = document.getElementById('password');

let isSignup = false;

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

toggleLink.addEventListener('click', e => {
  e.preventDefault();
  isSignup = !isSignup;
  fullNameField.hidden        = !isSignup;
  confirmPasswordField.hidden = !isSignup;
  btnLabel.textContent  = isSignup ? 'Registracija' : 'Prijava';
  toggleLink.textContent = isSignup ? 'Že imam račun? Prijava →' : 'Nimam računa? Registracija →';
  passwordInput.autocomplete = isSignup ? 'new-password' : 'current-password';
  errorEl.hidden   = true;
  successEl.hidden = true;
  document.getElementById('loginForm').reset();
});

document.getElementById('loginForm').addEventListener('submit', async e => {
  e.preventDefault();
  const email    = document.getElementById('email').value.trim();
  const password = passwordInput.value;

  errorEl.hidden   = true;
  successEl.hidden = true;

  if (!email || !password) return showError('Vnesite e-pošto in geslo.');

  if (isSignup) {
    const fullName       = document.getElementById('fullName').value.trim();
    const confirmPassword = document.getElementById('confirmPassword').value;
    if (!fullName)                  return showError('Vnesite ime in priimek.');
    if (password.length < 6)        return showError('Geslo mora imeti vsaj 6 znakov.');
    if (password !== confirmPassword) return showError('Gesli se ne ujemata.');

    setLoading(true);
    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: { data: { full_name: fullName } },
    });
    setLoading(false);

    if (error) return showError(error.message);

    if (data.session) {
      window.location.replace('app.html');
    } else {
      successEl.textContent = 'Registracija uspešna! Preverite e-pošto za potrditev računa.';
      successEl.hidden = false;
    }
  } else {
    setLoading(true);
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    setLoading(false);

    if (error) {
      showError(error.message === 'Invalid login credentials'
        ? 'Napačna e-pošta ali geslo.'
        : error.message);
      passwordInput.value = '';
      return;
    }
    window.location.replace('app.html');
  }
});

function showError(msg) {
  errorEl.textContent = msg;
  errorEl.hidden = false;
}

function setLoading(on) {
  loginBtn.disabled = on;
  btnLabel.hidden = on;
  loginBtn.querySelector('.btn-spinner').hidden = !on;
}
