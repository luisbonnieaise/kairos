// Núcleo agnóstico de provider do billing: vocabulário de status canônico,
// dedupe em billing_events e a única porta de escrita do entitlement
// (RPC aplicar_estado_assinatura). Reaproveitado por apple-webhook,
// google-webhook e verify-purchase para não duplicar lógica.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.47.0';

type Service = ReturnType<typeof createClient>;

// Mesmo vocabulário do CHECK em scripts/12_billing_multiplataforma.sql.
export type CanonicalStatus =
  | 'none' | 'incomplete' | 'incomplete_expired' | 'trialing' | 'active'
  | 'past_due' | 'canceled' | 'unpaid' | 'paused' | 'grace' | 'expired';

export type Provider = 'stripe' | 'apple' | 'google';

export interface EstadoCanonico {
  userId: string;
  provider: Provider;
  status: CanonicalStatus;
  productId: string | null;
  currentPeriodEnd: string | null; // ISO 8601 ou null
  cancelAtPeriodEnd?: boolean;
  providerSubId?: string | null;
}

// Critério premium — paridade EXATA com is_premium() (SQL) e
// lib/core/billing.dart::derivarPremium.
const STATUS_CONCEDE = new Set<string>(['active', 'trialing', 'grace']);

export function concedeAcesso(status: string | null, currentPeriodEnd: string | null): boolean {
  if (!status || !STATUS_CONCEDE.has(status)) return false;
  if (!currentPeriodEnd) return false;
  return new Date(currentPeriodEnd).getTime() > Date.now();
}

// ── Idempotência unificada (billing_events) ─────────────────────────────────
export async function eventoJaVisto(
  service: Service, provider: Provider, eventId: string,
): Promise<boolean> {
  const { data } = await service
    .from('billing_events')
    .select('event_id')
    .eq('provider', provider)
    .eq('event_id', eventId)
    .maybeSingle();
  return !!data;
}

// Marca o evento como visto. Falha silenciosa (exceto duplicidade): na pior
// hipótese o provider re-entrega e a RPC idempotente absorve.
export async function marcarEvento(
  service: Service, provider: Provider, eventId: string, type: string,
): Promise<void> {
  const { error } = await service
    .from('billing_events')
    .insert({ provider, event_id: eventId, type });
  if (error && (error as { code?: string }).code !== '23505') {
    console.error('Falha ao gravar billing_events:', error.message);
  }
}

// ── Escrita canônica do entitlement ─────────────────────────────────────────
// Única porta de escrita (mesma usada pelo stripe-webhook). Devolve o estado
// resultante já reduzido a { premium, current_period_end } para o client.
export async function aplicarEstado(
  service: Service, e: EstadoCanonico,
): Promise<{ premium: boolean; current_period_end: string | null }> {
  const { data, error } = await service.rpc('aplicar_estado_assinatura', {
    p_user_id:              e.userId,
    p_provider:             e.provider,
    p_status:               e.status,
    p_product_id:           e.productId,
    p_current_period_end:   e.currentPeriodEnd,
    p_cancel_at_period_end: e.cancelAtPeriodEnd ?? false,
    p_provider_sub_id:      e.providerSubId ?? null,
  });
  if (error) throw new Error(`aplicar_estado_assinatura: ${error.message}`);
  const row = data as { status?: string; current_period_end?: string | null } | null;
  return {
    premium: concedeAcesso(row?.status ?? null, row?.current_period_end ?? null),
    current_period_end: row?.current_period_end ?? null,
  };
}
