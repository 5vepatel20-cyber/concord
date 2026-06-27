'use client';

import { useState, type FormEvent } from 'react';

export default function EmailCapture() {
  const [email, setEmail] = useState('');
  const [status, setStatus] = useState<'idle' | 'submitting' | 'success'>('idle');

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    if (!email.trim()) return;
    setStatus('submitting');
    // TODO: wire to actual waitlist backend
    await new Promise((r) => setTimeout(r, 600));
    setStatus('success');
  };

  if (status === 'success') {
    return (
      <section className="email-capture container">
        <div className="email-capture-card">
          <p className="email-capture-success">
            You&apos;re on the list. We&apos;ll let you know when symptom tracking is ready.
          </p>
        </div>
      </section>
    );
  }

  return (
    <section className="email-capture container">
      <div className="email-capture-card">
        <h2>Get early access to symptom tracking</h2>
        <p>
          Decode is free for everyone. Sign up for early access when we launch
          daily symptom logging, trend detection, and shareable reports.
        </p>
        <form className="email-capture-form" onSubmit={handleSubmit}>
          <input
            type="email"
            required
            placeholder="you@example.com"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            disabled={status === 'submitting'}
          />
          <button type="submit" className="btn-primary" disabled={status === 'submitting'}>
            {status === 'submitting' ? 'Joining...' : 'Join waitlist'}
          </button>
        </form>
      </div>
    </section>
  );
}
