"use client";

import { useEffect } from "react";

export function MarkAsRead({
  conversationId,
  markAsReadAction,
}: {
  conversationId: string;
  markAsReadAction: (conversationId: string) => Promise<void>;
}) {
  useEffect(() => {
    markAsReadAction(conversationId);
  }, [conversationId, markAsReadAction]);

  return null;
}
