import { test, expect } from "@playwright/test";

test.describe("home page", () => {
  test("renders the cinematic landing page and key SEO tags", async ({ page }) => {
    await page.goto("/");

    await expect(page).toHaveTitle(/Euphoria Season 3 Release Date, Cast, Episodes & FAQ/);
    await expect(page.locator("h1")).toContainText("Euphoria Season 3");
    await expect(page.locator(".status-pill")).toContainText("April 15, 2026");

    await expect(page.locator('link[rel="canonical"]')).toHaveAttribute(
      "href",
      "https://euphoria-season-3.lol/"
    );
    await expect(page.locator('meta[name="description"]')).toHaveAttribute(
      "content",
      /release date, episode rollout, cast/i
    );
    await expect(page.locator('link[rel="icon"][href="/favicon.svg"]')).toHaveCount(1);

    const structuredData = await page.locator('script[type="application/ld+json"]').textContent();
    const parsed = JSON.parse(structuredData);
    const faqPage = parsed["@graph"].find((item) => item["@type"] === "FAQPage");
    const tvSeason = parsed["@graph"].find((item) => item["@type"] === "TVSeason");
    expect(faqPage.mainEntity).toHaveLength(5);
    expect(tvSeason.numberOfEpisodes).toBe(8);

    const headHtml = await page.locator("head").innerHTML();
    expect(headHtml).toContain("www.clarity.ms/tag/wbzt7enso6");
  });

  test("shows sections in the expected order and labels speculation clearly", async ({ page }) => {
    await page.goto("/");

    const sectionIds = await page.locator("main > section").evaluateAll((elements) =>
      elements.map((element) => element.id)
    );
    expect(sectionIds).toEqual([
      "hero",
      "what-we-know",
      "timeline",
      "cast",
      "rumor-watch",
      "faq",
      "sources"
    ]);

    await expect(page.locator("#rumor-watch .rumor-tag")).toHaveText([
      "Speculation",
      "Inference",
      "Speculation"
    ]);
  });

  test("faq interaction works and mobile layout does not overflow", async ({ page }) => {
    await page.goto("/");

    const firstItem = page.locator(".faq-item").first();
    await firstItem.locator("summary").click();
    await expect(firstItem).toHaveJSProperty("open", true);

    const noOverflow = await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth + 1
    );
    expect(noOverflow).toBeTruthy();
  });
});
