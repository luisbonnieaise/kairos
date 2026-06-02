-- ============================================================================
-- Kairo · 11_migracao_categorias_enum.sql
-- Migra `praticas.categoria` de rótulos em PT para enums ASCII estáveis.
--
-- Motivo: as chaves antigas ('Mente', 'Corpo', 'Disciplina', 'Relações',
-- 'Trabalho') eram exibidas como categoria mesmo quando o usuário usava o
-- app em outro idioma — e além disso 'Relações' carrega acento, o que é
-- frágil para chaves internas. A partir desta migração:
--   - práticas NOVAS são gravadas com o enum (mind/body/discipline/relations/work)
--   - práticas EXISTENTES são convertidas por este script
--   - o app continua aceitando AMBAS as chaves na exibição (via
--     `T.nomeCategoria(...)` em lib/core/i18n.dart), portanto rodar este
--     script é OPCIONAL: ele apenas padroniza o que está no banco.
--
-- Idempotente: rodar várias vezes não causa efeito colateral — só converte
-- linhas que ainda estão no padrão antigo.
-- ============================================================================

update public.praticas
   set categoria = case categoria
     when 'Mente'      then 'mind'
     when 'Corpo'      then 'body'
     when 'Disciplina' then 'discipline'
     when 'Relações'   then 'relations'
     when 'Trabalho'   then 'work'
     else categoria
   end
 where categoria in ('Mente', 'Corpo', 'Disciplina', 'Relações', 'Trabalho');
