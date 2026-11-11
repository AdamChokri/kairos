// SV-07: package-lock.json never resolves the vulnerable lodash again (plan WP4.5).
// Trivy (on every push and in the pipeline) and Dependabot are the detectors. This test is the offline guard for
// the dependency that was seeded: lodash 4.17.11 (CVE-2019-10744 and the advisories that came after it) must not
// come back through a merge conflict, a regenerated lockfile or a hurried downgrade. The floor is the release of
// the Dependabot pull request that fixed it (#3, 4.18.1). Raising it is a one-line change; lowering it is a
// decision, and goes to docs/decisions.md first.
import { describe, expect, it } from "vitest";
import lock from "../package-lock.json";

const FLOORS: Record<string, number[]> = { lodash: [4, 18, 1] };

function atLeast(version: string, floor: number[]): boolean {
  const parts = version.split(".").map((part) => Number.parseInt(part, 10) || 0);
  for (let i = 0; i < floor.length; i++) {
    const have = parts[i] ?? 0;
    if (have !== floor[i]) return have > floor[i];
  }
  return true;
}

describe("SV-07: the vulnerable releases do not come back", () => {
  for (const [name, floor] of Object.entries(FLOORS)) {
    it(`${name} resolves to ${floor.join(".")} or newer`, () => {
      const packages = lock.packages as Record<string, { version: string }>;
      const entry = packages[`node_modules/${name}`];
      expect(entry, `${name} is not in package-lock.json`).toBeDefined();
      expect(
        atLeast(entry.version, floor),
        `${name} ${entry.version} is below ${floor.join(".")}: it has known advisories (SV-07)`,
      ).toBe(true);
    });
  }
});
