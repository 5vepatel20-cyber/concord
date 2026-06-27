import Link from 'next/link';
import EmailCapture from '../components/EmailCapture';

const APP_URL = process.env.NEXT_PUBLIC_APP_URL || 'https://concord.so';

export default function HomePage() {
  return (
    <>
      <section className="hero container">
        <h1>Understand your medical reports in plain language</h1>
        <p>
          Paste or snap a photo of any medical document — discharge summary, lab
          results, visit notes — and get an instant plain-language breakdown
          with flagged abnormalities and questions for your care team.
        </p>
        <div className="hero-actions">
          <Link href={APP_URL} className="btn-primary">
            Decode a report &mdash; free
          </Link>
          <Link href={`${APP_URL}/sign-in`} className="btn-secondary">
            Sign in
          </Link>
        </div>
      </section>

      <section className="container">
        <div className="features">
          <div className="feature-card">
            <div className="feature-icon">&#128196;</div>
            <h3>Decode My Doctor&apos;s Report</h3>
            <p>
              Paste medical text or snap a photo. Concord extracts key
              information, flags abnormal lab values, and explains everything
              in plain language. No account needed.
            </p>
          </div>
          <div className="feature-card">
            <div className="feature-icon">&#128200;</div>
            <h3>Track symptoms over time</h3>
            <p>
              Log daily symptoms with a single tap. See worsening trends at a
              glance and generate one-page summaries to share with your care
              team.
            </p>
          </div>
          <div className="feature-card">
            <div className="feature-icon">&#129302;</div>
            <h3>Ask Atlas</h3>
            <p>
              Get AI-powered answers about your symptoms, medications, and
              treatment plan. Atlas helps you prepare for your next visit.
            </p>
          </div>
          <div className="feature-card">
            <div className="feature-icon">&#128737;</div>
            <h3>Private &amp; secure</h3>
            <p>
              Your health data stays yours. Decode works without an account.
              Sign up only when you&apos;re ready to track symptoms over time.
            </p>
          </div>
          <div className="feature-card">
            <div className="feature-icon">&#128221;</div>
            <h3>Share with your care team</h3>
            <p>
              Generate shareable cards with your decode results. Take them to
              your next appointment or send to a family member.
            </p>
          </div>
          <div className="feature-card">
            <div className="feature-icon">&#128138;</div>
            <h3>Medication tracking</h3>
            <p>
              Log medications mentioned in your reports, set reminders, and
              track adherence over time.
            </p>
          </div>
        </div>
      </section>

      <EmailCapture />

      <section className="disclaimer container">
        <p>
          Concord is not a medical device. It helps you understand your records
          between visits. Always follow your care team&apos;s guidance.
        </p>
      </section>

      <footer className="footer container">
        <p>&copy; {new Date().getFullYear()} Concord. All rights reserved.</p>
      </footer>
    </>
  );
}
