import { defineConfig, devices } from "@playwright/test";

const baseURL = process.env.BASE_URL || "http://127.0.0.1:4317";
const useLocalDevServer = !process.env.BASE_URL;

export default defineConfig({
  testDir: "./tests",
  fullyParallel: true,
  timeout: 30_000,
  expect: {
    timeout: 5_000
  },
  use: {
    baseURL
  },
  webServer: useLocalDevServer
    ? {
        command: "npm run dev -- --host 127.0.0.1 --port 4317",
        url: "http://127.0.0.1:4317",
        reuseExistingServer: false
      }
    : undefined,
  projects: [
    {
      name: "desktop-chromium",
      use: {
        ...devices["Desktop Chrome"]
      }
    },
    {
      name: "mobile-chromium",
      use: {
        ...devices["Pixel 7"]
      }
    }
  ]
});
