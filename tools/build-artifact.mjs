// Writes dist/artifact.html: index.html without the document wrapper tags,
// for hosting as a claude.ai Artifact (which supplies its own <head>/<body>).
import fs from 'fs';
const html = fs.readFileSync(new URL('../index.html', import.meta.url), 'utf8');
let body = html
  .replace(/<!doctype html>\s*/i, '')
  .replace(/<html[^>]*>\s*/i, '').replace(/<\/html>\s*/i, '')
  .replace(/<head>[\s\S]*?<!-- BODY-START -->\s*/i, '')
  .replace(/<!-- HEAD-END -->\s*<\/head>\s*<body>\s*/i, '')
  .replace(/<\/body>\s*/i, '');
fs.mkdirSync(new URL('../dist/', import.meta.url), { recursive: true });
fs.writeFileSync(new URL('../dist/artifact.html', import.meta.url), body);
console.log('wrote dist/artifact.html', body.length);
