# MATITA

Biblioteca pública e compartilhada de questões do ITA. Não há cadastro, e-mail ou senha: todos os visitantes usam o mesmo progresso, os mesmos simulados e o mesmo catálogo de resoluções.

## O que fica no repositório

- `Provas_Completas_ITA.pdf` e `Mapa_Questoes_ITA_2011-2025.pdf`: os PDFs estão na raiz do repositório e o site os abre diretamente dali. Como o repositório é público, qualquer pessoa pode baixar e compartilhar esses documentos.
- `supabase/seed.sql`: catálogo versionado com 429 questões válidas de Matemática e 90 de Inglês; ITA 2024.2 Q03 de Inglês está anulada.
- `index.html` e `app.js`: site MATITA sem tela de login.

## O que mantém o progresso sincronizado

O GitHub Pages só hospeda arquivos estáticos; ele não salva simulados, soluções e progresso compartilhado. Para sincronizar tudo entre dispositivos, a aplicação usa um projeto Supabase. Esse backend ainda precisa ser criado e conectado antes de o site funcionar integralmente. Sem ele, os PDFs e o código permanecem no repositório, mas não há sincronização do progresso.

No modo compartilhado, qualquer visitante pode criar simulados e registrar ou substituir resoluções. O progresso e as imagens/PDFs de resolução ficam públicos e podem ser alterados por qualquer pessoa. O site não oferece autoria individual nem proteção contra alterações indevidas.

## Preparar o Supabase

1. Crie um projeto Supabase.
2. No SQL Editor, execute `supabase/schema.sql` e depois `supabase/seed.sql`.
3. Copie a Project URL e a chave publicável (anon/publishable key). Nunca use `service_role` ou uma chave `secret` no site.

## Publicar no GitHub Pages

O repositório público já está em `https://github.com/Veronicafiorin23/MATITA`.

1. Em **Settings → Pages**, selecione **GitHub Actions** como fonte.
2. Em **Settings → Secrets and variables → Actions**, adicione:
   - variável `SUPABASE_URL`: Project URL;
   - secret `SUPABASE_PUBLISHABLE_KEY`: chave publicável/anon.
3. O workflow publica em `https://veronicafiorin23.github.io/MATITA/` depois que as configurações estiverem presentes.

A chave publicável é usada no navegador por design. As políticas RLS no schema permitem o modo aberto e compartilhado. O repositório contém os PDFs por escolha sua; ambos são publicamente acessíveis.

## Estrutura

- `.github/workflows/pages.yml`: publicação automática e cópia dos dois PDFs para o site.
- `scripts/write-config.mjs`: gera a configuração pública do Supabase no build.
- `supabase/schema.sql`: tabelas, políticas abertas e sorteio global sem repetição.
- `supabase/seed.sql`: catálogo inicial completo.

