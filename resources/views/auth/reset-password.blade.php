<!doctype html>
<html lang="id">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex,nofollow">
    <title>Atur Ulang Kata Sandi — Berkah POS</title>
    <style>
        :root { color-scheme: light; font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
        body { margin: 0; padding: 24px; background: #f4f6f8; color: #182230; }
        main { width: min(100%, 440px); margin: 8vh auto; padding: 28px; box-sizing: border-box; background: #fff; border: 1px solid #dde3e9; border-radius: 16px; }
        h1 { margin: 0 0 8px; font-size: 1.45rem; }
        p { line-height: 1.5; color: #475467; }
        label { display: block; margin: 18px 0 6px; font-weight: 600; }
        input { width: 100%; box-sizing: border-box; padding: 12px; font: inherit; border: 1px solid #98a2b3; border-radius: 8px; }
        button { margin-top: 22px; width: 100%; padding: 13px; border: 0; border-radius: 8px; background: #155eef; color: white; font: inherit; font-weight: 700; cursor: pointer; }
        button:disabled { opacity: .6; cursor: wait; }
        #status { min-height: 24px; overflow-wrap: anywhere; }
    </style>
</head>
<body>
<main>
    <h1>Atur ulang kata sandi</h1>
    <p>Gunakan tautan ini hanya jika Anda meminta pengaturan ulang kata sandi. Setelah berhasil, semua sesi lama akan dicabut.</p>
    <form id="reset-form" data-api-endpoint="{{ url('/api/v1/auth/password/reset') }}">
        <input type="hidden" name="token" value="{{ $token }}">
        <label for="email">Email akun</label>
        <input id="email" name="email" type="email" autocomplete="username" maxlength="254" required value="{{ request()->query('email', '') }}">
        <label for="password">Kata sandi baru</label>
        <input id="password" name="password" type="password" autocomplete="new-password" minlength="16" maxlength="4096" required>
        <label for="password_confirmation">Ulangi kata sandi baru</label>
        <input id="password_confirmation" name="password_confirmation" type="password" autocomplete="new-password" minlength="16" maxlength="4096" required>
        <button id="submit-button" type="submit">Simpan kata sandi</button>
        <p id="status" role="status" aria-live="polite"></p>
    </form>
</main>
<script>
(() => {
    const form = document.getElementById('reset-form');
    const button = document.getElementById('submit-button');
    const status = document.getElementById('status');
    form.addEventListener('submit', async (event) => {
        event.preventDefault();
        status.textContent = '';
        const data = new FormData(form);
        const password = String(data.get('password') || '');
        const confirmation = String(data.get('password_confirmation') || '');
        if (password !== confirmation) {
            status.textContent = 'Kata sandi tidak cocok.';
            return;
        }
        button.disabled = true;
        try {
            const response = await fetch(form.dataset.apiEndpoint, {
                method: 'POST',
                headers: { 'Accept': 'application/json', 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    email: data.get('email'),
                    token: data.get('token'),
                    password,
                    password_confirmation: confirmation
                })
            });
            const result = await response.json();
            status.textContent = result.message || 'Permintaan tidak dapat diproses.';
            if (response.ok) {
                form.reset();
                status.textContent = 'Kata sandi berhasil diperbarui. Silakan masuk kembali di aplikasi Berkah POS.';
            }
        } catch (_) {
            status.textContent = 'Tidak dapat terhubung. Periksa jaringan Anda dan coba lagi.';
        } finally {
            button.disabled = false;
        }
    });
})();
</script>
</body>
</html>
