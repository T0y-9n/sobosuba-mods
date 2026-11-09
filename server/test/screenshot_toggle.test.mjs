import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { test } from "node:test";

// Game-dependent scripts are checked here without starting the engine. The real
// settings and translations are exercised by settings.gd and text.gd.
for (const folder of ["mods/prime_sobo", "beta-1.3.8/prime_mod"]) {
  const source = async file => (await readFile(resolve("..", folder, file), "utf8")).replace(/\r/g, "");
  const body = (text, name) => {
    const start = text.indexOf(`\nfunc ${name}(`);
    assert.ok(start >= 0, `${name} exists`);
    const end = text.indexOf("\nfunc ", start + 1);
    return text.slice(start, end < 0 ? undefined : end);
  };

  test(`${folder}: screenshot switch follows send scores with independent nodes and signals`, async () => {
    const mod = await source("prime_sobo.gd");
    assert.match(mod, /install_send_toggle\(menu\)\n\tinstall_screenshot_toggle\(menu\)/);
    const install = body(mod, "install_screenshot_toggle");
    assert.match(install, /model: SoboMenuButtonBool = send_toggle/);
    assert.match(install, /value_for_copy\(model\.get\(prop\.name\), model, button\)/);
    assert.doesNotMatch(install, /DUPLICATE_SIGNALS/);
    assert.match(install, /send_toggle\.add_sibling\(button\)/);
    assert.match(install, /release_press\.connect\(on_screenshot_toggle_pressed\)/);
    assert.match(body(mod, "set_save_screenshots"), /prime_settings\.set_save_screenshots\(value\)/);
    assert.match(body(mod, "refresh_screenshot_toggle"), /set_value\(prime_settings\.save_screenshots\)/);
    assert.match(body(mod, "refresh_texts"), /screenshot_toggle\.label\.text = word\(SCREENSHOT_TEXT\)/);
  });

  test(`${folder}: screenshots are gated before waiting and at the delayed call`, async () => {
    const over = body(await source("prime_scores.gd"), "on_game_over");
    assert.match(over, /if not get_parent\(\)\.prime_settings\.save_screenshots:\n\t\treturn\n\tawait get_tree/);
    assert.match(over, /if get_parent\(\)\.prime_settings\.save_screenshots:\n\t\tsave_steam_screenshot\(score\)/);
  });

  test(`${folder}: self-test opts in using its own file and checks off leaves the handle alone`, async () => {
    const mod = await source("prime_sobo.gd");
    assert.match(body(mod, "_ready"), /prime_settings\.set_save_screenshots\(false\)/);
    assert.match(body(mod, "run_selftest"), /set_save_screenshots\(true\)/);
    const checks = body(mod, "selftest_screenshot_toggle");
    assert.match(checks, /screenshot_toggle\.release_press\.emit\(\)/);
    assert.match(checks, /await scores\.on_game_over\(\)/);
    assert.match(checks, /last_screenshot_handle == handle_before/);
    assert.match(checks, /board_fingerprint\(prime_settings\.PATH\) == real_settings_before/);
  });
}
