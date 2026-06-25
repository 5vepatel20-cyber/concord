// SEC-06: Audit logging middleware.
// Fire-and-forget insert into the audit_log table. Failures are captured by
// Sentry but never block the calling request handler.

import type { SupabaseClient } from "@supabase/supabase-js";
import { Sentry } from "./sentry.js";

export interface AuditEvent {
  patientId: string;
  actorId: string;
  action: string;
  entityType?: string;
  entityId?: string;
  details?: Record<string, unknown>;
  ipAddress?: string;
}

export async function logAudit(
  supabase: SupabaseClient,
  event: AuditEvent,
): Promise<void> {
  try {
    const { error } = await supabase.from("audit_log").insert({
      patient_id: event.patientId,
      actor_id: event.actorId,
      action: event.action,
      entity_type: event.entityType ?? null,
      entity_id: event.entityId ?? null,
      details: event.details ?? null,
      ip_address: event.ipAddress ?? null,
    });
    if (error) Sentry.captureException(error);
  } catch (e) {
    Sentry.captureException(e);
  }
}
