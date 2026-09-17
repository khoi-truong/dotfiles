import assert from "node:assert/strict";
import { test } from "node:test";
import { isDangerous } from "../extensions/permission-gate.ts";

// [command, asks]: the 67 cases from the original scratchpad harness, verbatim.
const legacy: [string, boolean][] = [
  ["rm -rf x", true],
  ["rm -fr build", true],
  ["rm -f -r x", true],
  ["rm -v -rf x", true],
  ["rm -R x", true],
  ["rm --recursive x", true],
  ["sudo ls", true],
  ["(cd ai && ./setup.sh)", true],
  ["bash \"./setup.sh\"", true],
  ["./setup.sh vscode", true],
  ["sh ai/setup.sh", true],
  ["setup.sh", true],
  ["mise use -g node@22", true],
  ["mise use --global node@22", true],
  ["mise use node@22 -g", true],
  ["mise i", true],
  ["mise install", true],
  ["mise upgrade", true],
  ["brew install jq", true],
  ["brew uninstall jq", true],
  ["brew bundle", true],
  ["brew bundle cleanup", true],
  ["defaults write x y", true],
  ["defaults delete x", true],
  ["defaults import x f", true],
  ["git push -f", true],
  ["git push origin +main", true],
  ["git push -fu origin x", true],
  ["git push --force-with-lease", true],
  ["git -C repo push -f", true],
  ["git -C repo reset --hard", true],
  ["git reset --hard HEAD", true],
  ["git clean -fd", true],
  ["git clean -d -f", true],
  ["git clean --force", true],
  ["git filter-branch --all", true],
  ["DOTFILES=x ./setup.sh", true],
  ["time ./setup.sh", true],
  ["env ./setup.sh", true],
  ["bash -x setup.sh", true],
  ["sh -c './setup.sh'", true],
  ["echo hi\n./setup.sh", true],
  ["mise use -gy node@22", true],
  ["xargs rm -rf", true],
  ["rm file.txt", false],
  ["rm -f file", false],
  ["shellcheck ai/setup.sh", false],
  ["bash -n setup.sh", false],
  ["git diff ai/setup.sh", false],
  ["cat setup.sh", false],
  ["cat setup.sh.bak", false],
  ["brew bundle check", false],
  ["brew bundle list", false],
  ["brew info jq", false],
  ["mise ls", false],
  ["mise use node@22", false],
  ["git push origin main", false],
  ["git push -u origin feat/x", false],
  ["git reset --soft HEAD~1", false],
  ["git clean -n", false],
  ["git -C repo status", false],
  ["defaults read x", false],
  ["npm run format", false],
  ["bash -n ai/setup.sh", false],
  ["sh -n setup.sh", false],
  ["echo setup.sh", false],
  ["vim setup.sh", false],
];

const added: [string, boolean][] = [
  // git rm -r only touches the index and tracked files.
  ["git rm -r --cached x", false],
  ["which git\nrm -rf build", true],
  ["git -C r rm -r x", false],
  ["git status && rm -rf x", true],
  ["find . -delete", true],
  ["find . -name x -exec rm {} +", true],
  ["find . -name x -execdir /bin/rm {} +", true],
  ["find . -name x -print", false],
  // Pinned gap: interpreter one-liners are not caught.
  [`python3 -c "import shutil; shutil.rmtree('x')"`, false],
];

test("legacy table is complete", () => {
  assert.equal(legacy.length, 67);
});

for (const [command, want] of [...legacy, ...added]) {
  test(`${want ? "asks" : "allows"}: ${JSON.stringify(command)}`, () => {
    assert.equal(isDangerous(command), want);
  });
}
