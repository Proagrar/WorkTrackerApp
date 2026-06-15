import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';
import { SUPABASE_URL, SUPABASE_ANON_KEY } from './config.js';

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

const errorEl   = document.getElementById('loginError');
const successEl = document.getElementById('loginSuccess');
const loginBtn  = document.getElementById('loginBtn');
const btnLabel  = loginBtn.querySelector('.btn-label');

const fullNameField        = document.getElementById('fullNameField');
const emailField           = document.getElementById('emailField');
const passwordField        = document.getElementById('passwordField');
const confirmPasswordField = document.getElementById('confirmPasswordField');
const passwordLabel        = document.getElementById('passwordLabel');
const confirmPasswordLabel = document.getElementById('confirmPasswordLabel');
const toggleLink           = document.getElementById('authToggleLink');
const forgotLink           = document.getElementById('forgotPasswordLink');

// mode: 'login' | 'signup' | 'reset' | 'recovery'
let mode = 'login';

function setMode(newMode) {
  mode = newMode;
  errorEl.hidden   = true;
  successEl.hidden = true;
  document.getElementById('loginForm').reset();

  fullNameField.hidden        = mode !== 'signup';
  emailField.hidden           = mode === 'recovery';
  passwordField.hidden        = mode === 'reset';
  confirmPasswordField.hidden = mode !== 'signup' && mode !== 'recovery';

  passwordLabel.textContent        = mode === 'recovery' ? 'Novo geslo'        : 'Geslo';
  confirmPasswordLabel.textContent = mode === 'recovery' ? 'Potrdi novo geslo' : 'Potrdi geslo';

  const labels = { login: 'Prijava', signup: 'Registracija', reset: 'Pošlji navodila', recovery: 'Nastavi geslo' };
  btnLabel.textContent = labels[mode];

  toggleLink.hidden = mode === 'recovery';
  toggleLink.textContent = mode === 'signup' ? 'Že imam račun? Prijava →'
    : mode === 'reset'  ? '← Nazaj na prijavo'
    : 'Nimam računa? Registracija →';

  forgotLink.hidden = mode !== 'login';
}

// Detect password recovery link (user clicked email link)
supabase.auth.onAuthStateChange((event) => {
  if (event === 'PASSWORD_RECOVERY') setMode('recovery');
});

// Redirect if already logged in
supabase.auth.getSession().then(({ data: { session } }) => {
  if (session && mode !== 'recovery') window.location.replace('app.html');
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

toggleLink.addEventListener('click', () => {
  if (mode === 'login')        setMode('signup');
  else if (mode === 'signup')  setMode('login');
  else if (mode === 'reset')   setMode('login');
});

forgotLink.addEventListener('click', () => setMode('reset'));

document.getElementById('loginForm').addEventListener('submit', async e => {
  e.preventDefault();
  errorEl.hidden   = true;
  successEl.hidden = true;

  // ── Reset: send recovery email ──────────────────────────────
  if (mode === 'reset') {
    const email = document.getElementById('email').value.trim();
    if (!email) return showError('Vnesite e-pošto.');
    setLoading(true);
    const { error } = await supabase.auth.resetPasswordForEmail(email, {
      redirectTo: window.location.origin + window.location.pathname,
    });
    setLoading(false);
    if (error) return showError(error.message);
    successEl.textContent = 'Preverite e-pošto za navodila za ponastavitev gesla.';
    successEl.hidden = false;
    return;
  }

  // ── Recovery: set new password ──────────────────────────────
  if (mode === 'recovery') {
    const password        = document.getElementById('password').value;
    const confirmPassword = document.getElementById('confirmPassword').value;
    if (password.length < 6)         return showError('Geslo mora imeti vsaj 6 znakov.');
    if (password !== confirmPassword) return showError('Gesli se ne ujemata.');
    setLoading(true);
    const { error } = await supabase.auth.updateUser({ password });
    setLoading(false);
    if (error) return showError(error.message);
    successEl.textContent = 'Geslo je nastavljeno. Preusmerjanje...';
    successEl.hidden = false;
    setTimeout(() => window.location.replace('app.html'), 1500);
    return;
  }

  const email    = document.getElementById('email').value.trim();
  const password = document.getElementById('password').value;
  if (!email || !password) return showError('Vnesite e-pošto in geslo.');

  // ── Signup ──────────────────────────────────────────────────
  if (mode === 'signup') {
    const fullName        = document.getElementById('fullName').value.trim();
    const confirmPassword = document.getElementById('confirmPassword').value;
    if (!fullName)                   return showError('Vnesite ime in priimek.');
    if (password.length < 6)         return showError('Geslo mora imeti vsaj 6 znakov.');
    if (password !== confirmPassword) return showError('Gesli se ne ujemata.');
    setLoading(true);
    const { data, error } = await supabase.auth.signUp({
      email, password,
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
    return;
  }

  // ── Login ───────────────────────────────────────────────────
  setLoading(true);
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  setLoading(false);
  if (error) {
    showError(error.message === 'Invalid login credentials'
      ? 'Napačna e-pošta ali geslo.'
      : error.message);
    document.getElementById('password').value = '';
    return;
  }
  window.location.replace('app.html');
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
