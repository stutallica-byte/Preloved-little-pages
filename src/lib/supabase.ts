import { createClient, type SupabaseClient } from '@supabase/supabase-js';

let client: SupabaseClient | undefined;

const fetchWithTimeout: typeof fetch = (input, init) => {
  const controller = new AbortController();
  const requestSignal = init?.signal;
  const relayAbort = () => controller.abort(requestSignal?.reason);

  if (requestSignal?.aborted) {
    relayAbort();
  } else {
    requestSignal?.addEventListener('abort', relayAbort, { once: true });
  }

  const timeout = setTimeout(
    () => controller.abort(new DOMException('Supabase request timed out.', 'TimeoutError')),
    15_000,
  );

  return fetch(input, { ...init, signal: controller.signal }).finally(() => {
    clearTimeout(timeout);
    requestSignal?.removeEventListener('abort', relayAbort);
  });
};

export function getSupabaseClient(): SupabaseClient {
  if (client) return client;

  const supabaseUrl = import.meta.env.PUBLIC_SUPABASE_URL;
  const supabasePublishableKey = import.meta.env.PUBLIC_SUPABASE_PUBLISHABLE_KEY;

  if (!supabaseUrl || !supabasePublishableKey) {
    throw new Error(
      'Supabase is not configured. Set PUBLIC_SUPABASE_URL and PUBLIC_SUPABASE_PUBLISHABLE_KEY in your .env file.',
    );
  }

  client = createClient(supabaseUrl, supabasePublishableKey, {
    global: { fetch: fetchWithTimeout },
  });
  return client;
}
