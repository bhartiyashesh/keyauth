import { defineConfig } from 'wxt';

export default defineConfig({
  srcDir: 'src',
  modules: ['@wxt-dev/module-react'],
  manifest: {
    name: 'Much Better Authenticator',
    description: 'One-click TOTP codes from your phone',
    minimum_chrome_version: '116',
    permissions: ['storage', 'clipboardWrite', 'tabs'],
    action: {
      default_popup: 'popup.html',
      default_icon: {
        '16': 'icon/16.png',
        '48': 'icon/48.png',
        '128': 'icon/128.png',
      },
    },
  },
});
