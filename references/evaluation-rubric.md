# Evaluation Rubric (Engineering & General Decisions)

Use this checklist during **Step 3 (Explain material risks)** to
prevent blind spots without inventing artificial objections.

Version 2.1.0 · 2026-11-19. Consult only on complex
multi-dimension reviews; do not preload on routine turns or lightweight models.
Read only dimensions relevant to the current review; this is not a mandatory
checklist for simple answers or authorized execution.

Before assigning severity, record the goal, relevant conditions, and evidence
origin: verified, user-provided, inferred, or unknown. Explain uncertainty in plain
language rather than inventing numerical confidence. User-provided constraints
can be used as stated; an inference is not a demonstrated defect.

---

## Part A: General Review Dimensions (通用评审维度)

1. **Premise & Logic Integrity (前提与逻辑自洽性)**
   - Is the premise verified, user-provided, inferred, or unresolved?
   - Does the conclusion concern design feasibility, implementation correctness,
     or suitability for a stated goal? Avoid conflating these judgments.
   - Are there causal leaps, survivorship bias, XY problems (where the proposed
     method conflicts with the explicitly stated goal), or false dichotomies ("either A or B")?
   - Does the solution actually solve the root problem or only a symptom?

2. **Constraint & Resource Reality (资源与约束可行性)**
   - Are time, budget, skill/team bandwidth, permissions, and external dependencies realistic?
   - Which missing parameter would flip the outcome from viable to failing?

3. **Asymmetric Downside & Reversibility (最坏情况与可逆性)**
   - If this fails, is it cheap to roll back (two-way door) or costly/irreversible (one-way door)?
   - What is the worst plausible failure mode, and can the user survive it?

4. **Second-Order & Long-Term Effects (二阶效应与隐性代价)**
   - What happens 3-12 months later if this succeeds initially?
   - Does short-term convenience create high ongoing maintenance, lock-in, or coordination drag?

---

## Part B: Software Engineering Track (编程与架构场景扩展)

Scan only the dimensions relevant to the change:

1. **Correctness & Edge Cases (正确性与边界)**
   - Null/empty/malformed inputs, concurrency races, idempotency, partial failures, rollback/retry safety.
   - Backward compatibility for existing callers, schemas, migrations, and API contracts.

2. **Codebase Fit & Complexity (代码库适配与复杂度)**
   - Does the repo already have a helper, pattern, or dependency that solves this?
   - Does the change introduce hidden coupling, leaky abstractions, or unnecessary layers?

3. **Security, Privacy & Failure Blast Radius (安全与影响半径)**
   - Auth/authz bypasses, injection, secret exposure, unbounded queries/payloads, unvalidated external input.
   - How wide is the failure domain if this module misbehaves?

4. **Performance & Resource Footprint (性能与开销)**
   - N+1 queries, blocking sync calls in hot paths, unbounded memory/cache growth, missing timeouts.

5. **Testability & Operability (可测性与可运维性)**
   - Can behavior be verified cleanly without brittle mocks? Are errors observable (logs/metrics/alerts)?
   - Are failures recorded before an aggregator observes them? An outer
     allSettled cannot recover errors already swallowed by an inner catch.

---

## Part C: Everyday / Business / Career / Personal Decisions (日常与非编程场景扩展)

Scan only relevant dimensions (avoid lecturing on low-stakes casual questions):

1. **Opportunity Cost (机会成本)**
   - What high-value alternative is crowded out by spending time/money/attention here?

2. **Incentives & Human Friction (激励与执行阻力)**
   - Does the plan rely on unrealistic willpower, other people acting against their own incentives, or ideal behavior?

3. **Information & Validation Gap (信息差与最小试错)**
   - Instead of going all-in, what is the cheapest experiment/prototype that tests the riskiest assumption in days?

4. **Explicit Urgency, Frustration & Sunk-Cost Pressure (显式紧迫感、受挫与沉没成本压力)**
   - Only when the user explicitly expresses frustration, panic, deadline pressure,
     or past sunk cost (never speculate about unstated emotions): check whether
     that pressure is driving an irreversible, high-downside move.

5. **Domain Boundary Humility (高风险领域边界)**
   - For medical, legal, tax, or major financial decisions: explicitly state limits of certainty, avoid false precision, and highlight what requires qualified verification.

---

## Severity Calibration (严重度标尺)

| Level | Criteria | Action |
| :--- | :--- | :--- |
| 🔴 **Blocker / Critical** | Supported defect breaks a required outcome, violates a verified hard constraint, or exposes the task to unacceptable risk under stated conditions. | Explain evidence, trigger, and impact; fix or redesign before the affected step. |
| 🟡 **Material Trade-off** | Works under current assumptions, but carries significant cost, complexity, debt, fragility, or lock-in. | Explain the trade-off and useful mitigation; an already informed choice does not require repeated approval. |
| 🟢 **Minor** | Style, naming, minor ergonomics, small edge polish. | Mention briefly (or skip if noisy). |

Severity reflects impact and exposure, not alarming vocabulary. A hypothetical
risk should be conditional, not described as an observed incident. If no material
defect is supported, say so; do not invent an alternative or missing requirement.

When challenged, check both the evidence and your inference. Self-discovered
errors and valid reasoning can justify correction without new user facts. A
changed user preference can change the recommendation without changing facts.
