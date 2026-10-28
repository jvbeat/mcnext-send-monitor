# mcnext-send-monitor

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A send monitor for Marketing Cloud Next (Marketing Cloud on the Salesforce platform with Data Cloud). Every 15 minutes it reads what happened to the sends and flows, and when something did not reach people it e-mails the marketing team, and posts a bell notification, with the cause and what to fix.

In Marketing Cloud Next, a rejected message does not show up in the flow. The flow ends as completed, the reason sits in a Data Cloud engagement table, and the team usually finds out when a customer says the message never arrived. This monitor reads those tables and the flow run records, and turns the platform error codes into instructions for whoever builds the send. It is plain Apex with configuration in custom metadata, with no AI and no managed package. Nothing in this repository contains client code, metadata or data.

## What it checks

WhatsApp and SMS, from `ssot__MessageEngagement__dlm`:

- A content rejected by a content or platform error, such as a variable typed as text instead of picked in the field selector, a content whose number of variables differs from the template approved by Meta, or a variable without a value. A small send rejected entirely by the Meta template also alerts, below the minimum.
- A large share of a send not delivered because of the audience: no mobile phone, no consent, an open service conversation, a number that is not on WhatsApp, or the Meta marketing message limit.
- A variable that went out without data. When one value fills a large share of a variable that otherwise varies per person, or a large share of the messages carries one of the configured default texts, the people who got it have no data for that field in the segment.

E-mail, from `ssot__EmailEngagement__dlm`:

- A large share of a send not sent because of the audience: hard bounce in an earlier send, no e-mail address, no opt-in, or consent refused.
- E-mails not sent for a reason the monitor does not know, reported with the platform's own text.
- A hard bounce rate above the limit, which hurts the delivery of every e-mail of the domain.

Flows, from `FlowRecordVersionOccurrence` and `FlowRecordVersion`:

- A run that failed and sent nothing, such as a segment that could not be read.
- A run where people hit an error inside the flow.
- A paused flow.
- A recurring flow that did not run today. A flow counts as recurring at a time slot when it ran around that time on at least five of the last seven days, including the same weekday last week.

Each alert goes out once per problem and per day (once per run for flow runs), and stays recorded in the Send Monitor Alert object. A check that fails, for example because the scheduling user cannot read Data Cloud, is reported as an alert and does not stop the others.

An alert reads like this:

```
WhatsApp rejected: Welcome journey day 1

120 of 300 messages of "Welcome journey day 1" were rejected in the last 3 hours and reached nobody.

- 118 with WA-132000: the content has a number of variables different from the template approved by Meta (the content sends 1 and the template has none). Remove the variable from the content.
- 2 with SF-3003: the platform rejected the message with an internal error. In the cases measured so far, the cause was a variable typed as text or content that does not match the template approved by Meta.

Do not send again before fixing the content and checking it in Preview and Test.
```

## Install

Requirements: Marketing Cloud Next with Data Cloud, and a user who can read Data Cloud to own the schedule.

```
sf project deploy start --source-dir force-app --target-org <alias>
```

For alert texts and explanations in Portuguese, deploy the locale on top:

```
sf project deploy start --source-dir locales/pt-BR --target-org <alias>
```

Then:

1. Add the people who should receive the alerts to the public group Send Monitor Recipients.
2. Assign them the permission set Send Monitor Viewer, so the bell notification opens the alert.
3. Run [scripts/schedule.apex](scripts/schedule.apex) once, as the user who will own the schedule: `sf apex run --file scripts/schedule.apex --target-org <alias>`.
4. Optionally run [scripts/run-now.apex](scripts/run-now.apex) to see what the monitor finds right away.

In an org without Data Cloud, leave out `SendMonitorDataCloud` and `SendMonitorDataCloudTest`, which only compile with Data Cloud. The flow checks keep working and the Data Cloud checks return nothing.

## Configure

Everything is in custom metadata, so it changes without code:

- Send Monitor Setting, record Default: window in hours, minimum rejections, audience and bounce ratios, the missing-data ratio, minimum messages and default texts, the grace time for missed runs, the recipients group, the sender address, the subject prefix, the time zone and one switch per check.
- Send Monitor Code: one record per error code or not-sent reason, with its category (CONTENT, AUDIENCE or PLATFORM) and the explanation shown in the alert. A code not in the list is classified by its prefix: Meta template errors (WA-132xxx) as content, other Meta errors (WA-13xxxx) as audience, anything else as platform, explained with the platform's message.

## How it was tested

- 28 Apex unit tests, 97% coverage, run in a sandbox with simulated Data Cloud answers and flow runs.
- The queries the checks build were run read-only against a production org with Marketing Cloud Next, and the rules were replayed on one week of its data. They found the incidents the team had dealt with by hand that week: WhatsApp contents with one variable more than the Meta template, rejected by the hundreds, and two segment-triggered flow runs that failed reading the segment and sent nothing. On an earlier send, the missing-data rule found the variable that went out with the default text to most of the audience. The missed-run rule stayed quiet on a day when every recurring flow ran.

## Limits

- An e-mail variable without data does not fail the send: the e-mail goes out with the default text and nothing is recorded, so the missing-data check covers WhatsApp and SMS only.
- The missing-data check is a heuristic. A variable with few values by design, such as the name of the account manager, is not reported; a default text used in every message is only reported when it is listed in Fallback Values.
- SMS uses the same table as WhatsApp, but it was not tested with real SMS data.
- Inside tests, Data Cloud does not answer, so `SendMonitorDataCloudTest` covers the call and not the result.

<details>
<summary>Em português</summary>

Monitor de envios para o Marketing Cloud Next (o Marketing Cloud na plataforma Salesforce, com Data Cloud). A cada 15 minutos ele confere o que aconteceu com os envios e os fluxos e, quando algo não chegou às pessoas, avisa o time de marketing por e-mail e pelo sino do Salesforce com a causa e o que corrigir.

No Marketing Cloud Next, a mensagem recusada não aparece no fluxo: o fluxo termina como concluído, o motivo fica numa tabela de engajamento do Data Cloud e o time costuma descobrir quando o cliente reclama. O monitor lê essas tabelas e os registros de execução dos fluxos e traduz os códigos de erro da plataforma em instrução para quem monta o envio. É Apex com configuração em custom metadata, sem IA e sem pacote gerenciado. Nenhum arquivo deste repositório contém código, metadado ou dado de cliente.

Ele confere WhatsApp e SMS (conteúdo recusado, base que não recebe e variável que saiu sem dado), e-mail (base sem e-mail, sem opt-in ou com hard bounce anterior, motivo desconhecido e taxa de hard bounce alta) e fluxos (execução com falha, execução com erro, fluxo pausado e fluxo recorrente que não executou hoje). Para os textos em português, instale também a pasta `locales/pt-BR`. Os passos de instalação, a configuração e os limites estão nas seções acima.

</details>
