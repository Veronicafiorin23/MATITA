# MATITA

Biblioteca pública e compartilhada de questões do ITA. Não há cadastro, e-mail ou senha: todos os visitantes usam o mesmo progresso, os mesmos simulados e o mesmo catálogo de resoluções, sincronizados pelo Supabase.

## Acesso público e compartilhamento

O site, os PDFs de origem e as resoluções são públicos. Qualquer visitante pode registrar ou substituir uma resolução e criar simulados; as alterações afetam o progresso de todos. Este modo não oferece privacidade, autoria individual ou proteção contra alterações indevidas. O repositório guarda apenas o código; não envie PDFs nem credenciais para o GitHub.

## Preparar o Supabase

1. Crie um projeto Supabase.
2. No SQL Editor, execute `supabase/schema.sql` e depois `supabase/seed.sql`.
3. Em **Storage**, confirme os buckets públicos `proof-pdfs` e `user-resolutions`, criados pelo schema.
4. Faça upload dos PDFs no bucket `proof-pdfs`, usando estes nomes exatos:
   - `Provas_Completas_ITA.pdf`
   - `Mapa_Questoes_ITA_2011-2025.pdf`
5. Copie a Project URL e a chave publicável (anon/publishable key). Não use a `service_role` nem uma chave `secret` no site.

## Publicar no GitHub Pages

1. Crie um repositório público chamado **MATITA** na conta `Veronicafiorin23`.
2. Envie o conteúdo desta pasta para a branch `main`.
3. Em **Settings → Pages**, selecione **GitHub Actions** como fonte.
4. Em **Settings → Secrets and variables → Actions**, adicione:
   - variável `SUPABASE_URL`: Project URL do Supabase;
   - secret `SUPABASE_PUBLISHABLE_KEY`: chave publicável/anon do Supabase.
5. O workflow publicará em `https://veronicafiorin23.github.io/MATITA/` quando as configurações estiverem presentes.
6. PDFs não devem ser enviados ao GitHub; eles são servidos pelo bucket público do Supabase.

A chave publicável aparece no navegador por design. As políticas RLS do schema limitam o acesso às tabelas necessárias para o funcionamento compartilhado. Como a aplicação é aberta e colaborativa, qualquer pessoa pode fazer alterações no progresso compartilhado e enviar/remover arquivos de resolução.

## Arquivos

- `index.html`, `app.js`: interface MATITA sem login.
- `supabase/schema.sql`: banco, permissões públicas e sorteio sem repetição global.
- `supabase/seed.sql`: catálogo inicial (429 questões válidas de Matemática e 90 de Inglês; ITA 2024.2 Q03 de Inglês anulada).
- `.github/workflows/pages.yml`: publicação automática pelo GitHub Pages.
- `scripts/write-config.mjs`: gera a configuração pública no build do site.

