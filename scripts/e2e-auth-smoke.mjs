#!/usr/bin/env node
import { createHash } from "node:crypto";
import { execSync } from "node:child_process";

const baseUrl = process.env.CHATTEA_GRAPHQL_URL ?? "http://127.0.0.1:4000/graphql";
const phone = process.env.CHATTEA_PHONE || `010${Math.floor(10000000 + Math.random() * 90000000)}`;
const pepper = process.env.PHONE_CODE_PEPPER ?? "dev-only-pepper";
const dbUrl = {
  password: process.env.POSTGRES_PASSWORD || "chattea-dev",
  host: process.env.POSTGRES_HOST || "127.0.0.1",
  port: process.env.POSTGRES_PORT || "5433",
  user: process.env.POSTGRES_USER || "chattea",
  name: process.env.POSTGRES_DB || "chattea",
};

const gql = async (query, variables = {}, headers = {}) => {
  const response = await fetch(baseUrl, {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: JSON.stringify({ query, variables }),
  });

  return response.json();
};

const e164 = `+82${phone.slice(1)}`;

const request = await gql(
  `mutation RequestPhoneCode($phone: String!) { requestPhoneCode(phone: $phone) { ok } }`,
  { phone },
);
if (request.errors) {
  console.error("requestPhoneCode failed", JSON.stringify(request));
  process.exit(1);
}

const hashRow = execSync(
  `PGPASSWORD=${dbUrl.password} psql -h ${dbUrl.host} -p ${dbUrl.port} -U ${dbUrl.user} -d ${dbUrl.name} -Atc "SELECT code_hash FROM phone_verifications WHERE phone_e164='${e164}' ORDER BY created_at DESC LIMIT 1;"`,
  { encoding: "utf8" },
).trim();

let code = "";
for (let index = 0; index < 1_000_000; index += 1) {
  const candidate = String(index).padStart(6, "0");
  const hash = createHash("sha256").update(`${e164}:${candidate}:${pepper}`).digest("hex");
  if (hash === hashRow) {
    code = candidate;
    break;
  }
}

if (!code) {
  console.error("failed to recover sms code hash");
  process.exit(1);
}

const verify = await gql(
  `mutation VerifyPhoneCode($phone: String!, $code: String!) { verifyPhoneCode(phone: $phone, code: $code) { __typename ... on SignupRequiredPayload { status signupToken } ... on LoginPayload { status session { token } user { phoneE164 } } } }`,
  { phone, code },
);
if (verify.errors) {
  console.error("verifyPhoneCode failed", JSON.stringify(verify));
  process.exit(1);
}

if (verify.data?.verifyPhoneCode?.__typename !== "SignupRequiredPayload") {
  console.error("expected SignupRequiredPayload", JSON.stringify(verify));
  process.exit(1);
}

const complete = await gql(
  `mutation CompletePhoneSignup($signupToken: String!, $nickname: String!, $termsAccepted: Boolean!) {
    completePhoneSignup(signupToken: $signupToken, nickname: $nickname, intro: "", termsAccepted: $termsAccepted) {
      session { token }
      user { phoneE164 }
    }
  }`,
  {
    signupToken: verify.data.verifyPhoneCode.signupToken,
    nickname: "tea",
    termsAccepted: true,
  },
);
if (complete.errors) {
  console.error("completePhoneSignup failed", JSON.stringify(complete));
  process.exit(1);
}

const me = await gql(
  `query { me { phoneE164 intro } }`,
  {},
  { authorization: `Bearer ${complete.data.completePhoneSignup.session.token}` },
);
if (me.errors || me.data?.me?.phoneE164 !== e164) {
  console.error("me failed or mismatch", JSON.stringify(me));
  process.exit(1);
}

console.log(JSON.stringify({ status: "ok", phoneE164: me.data.me.phoneE164, intro: me.data.me.intro }));
