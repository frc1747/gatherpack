# BL-016: Inline code in Markdown shows up as an empty code editor

| | |
|---|---|
| Kind | upstream bug |
| Priority | low |
| Status | waiting |
| Added | 2026-10-10 |
| Upstream base checked | `86ab397` |
| Planned branch | `feature/inline-code-display` (from `upstream/main`) |
| Upstream issue / PR | none yet |

## Summary

Any inline `<code>` on a page turns into an empty, read-only CodeMirror editor showing only the line number "1". The text is lost. Markdown with backticks hits this anywhere GatherPack renders Markdown through `md` (announcements, questions, replies, widgets). Upstream's own OAuth applications list hits it too.

Found 2026-10-10 in the Northwind sample data: the "Welcome to Northwind" widget had three backtick spans, and each one showed as an empty editor box. The sample data now uses bold instead, so this item is only the upstream fix.

## Evidence (upstream `86ab397`)

`app/javascript/code_editor.js:99-103`, run every 500 ms after `turbo:load`:

```js
document.querySelectorAll("code").forEach(codeElem => {
    let codeLang = codeElem.getAttribute("data-lang");
    view = genCodeEditor(codeElem.firstChild.innerText, codeLang, true, "json");
    codeElem.replaceWith(view.dom);
});
```

- It targets **every** `<code>` on the page.
- It reads `codeElem.firstChild.innerText`. That works only for upstream's own nesting, `<code data-lang="…"><pre>…</pre></code>` (`hooks/show.html.erb:9`, `reports/show.html.erb:8`, `reports/run.html.erb:8`, `gateways/show.html.erb:9,12`, `ledger_entries/_ledger_entry_card.html.erb:59`), where the first child is a `<pre>` element.
- For inline code (`<code>text</code>`), the first child is a Text node. Text nodes have no `innerText`, so the editor gets `undefined` and comes out empty.
- Upstream inline uses affected today: `oauth_applications/index.html.erb:35,37` (client uid and redirect URI), `doorkeeper/authorizations/show.html.erb:6` (the authorization code, which is the whole point of that page) and `doorkeeper/authorizations/new.html.erb:5`. Redcarpet output (`ApplicationHelper#md`, `application_helper.rb:101`) also produces inline `<code>` for backticks and `<pre><code>` for fenced blocks.

## Proposed fix

Only convert the block form, and read the text robustly:

```js
document.querySelectorAll("code > pre").forEach(pre => {
    let codeElem = pre.parentElement;
    let codeLang = codeElem.getAttribute("data-lang");
    view = genCodeEditor(pre.textContent, codeLang, true, "json");
    codeElem.replaceWith(view.dom);
});
```

Inline `<code>` then renders as normal Bootstrap inline code. Open questions for the branch:

- Should Markdown fenced blocks (`<pre><code>`, the usual nesting) also become editors? Probably leave them as plain `<pre>`; that's a separate feature.
- Check that the 500 ms interval doesn't re-process anything (it replaces the element, so a converted block is gone from the next query).

## Hooks

None. This is display-only JavaScript; no records change.

## Tests

- A system test (or a JS-free check of the rendered page plus a manual browser check, if upstream has no JS system tests) showing a Markdown announcement with backticks displays the code text.
- Hooks and Reports pages still show their code in the editor.
- Manual: OAuth applications list shows the uid and redirect URI.

## Fork strategy notes

- Edits an upstream file (`app/javascript/code_editor.js`), so it is its own `feature/*` branch from `upstream/main`, written to go upstream unchanged. Record the file in `FORK.md` when the branch exists.
- Small, generic bug fix: a good upstream PR candidate. Confirm with Corey before opening the issue or PR.

## Draft upstream issue

> **Inline `<code>` is replaced by an empty code editor**
>
> `code_editor.js` converts every `<code>` element into a read-only CodeMirror view and reads its text from `firstChild.innerText`. For inline code (Markdown backticks, the OAuth application list, the Doorkeeper authorization code page) the first child is a text node, which has no `innerText`, so the editor is empty and the text disappears. Limiting the conversion to `code > pre` (the nesting the Hooks and Reports pages use) and reading `textContent` fixes it.
