import { useEffect, useState } from 'react'
import { api, hasToken, setToken, setUnauthorizedHandler } from './api'
import Overview from './pages/Overview'
import Drivers from './pages/Drivers'
import Tariffs from './pages/Tariffs'
import Orders from './pages/Orders'

const tabs = [
  { id: 'overview', label: 'Обзор' },
  { id: 'drivers', label: 'Водители' },
  { id: 'orders', label: 'Заказы' },
  { id: 'tariffs', label: 'Тарифы' },
] as const
type Tab = (typeof tabs)[number]['id']

export function Mark({ size = 28 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 100 100" aria-hidden="true">
      <path d="M24,84 L24,50 A26,26 0 0 1 76,50 L76,84" fill="none" stroke="currentColor" strokeWidth="15" strokeLinecap="round" strokeLinejoin="round" />
      <circle cx="50" cy="68" r="9" fill="var(--gold)" />
    </svg>
  )
}

export default function App() {
  const [authed, setAuthed] = useState(hasToken())
  const [tab, setTab] = useState<Tab>('overview')

  useEffect(() => setUnauthorizedHandler(() => setAuthed(false)), [])

  if (!authed) return <Login onDone={() => setAuthed(true)} />

  return (
    <div className="shell">
      <header className="top">
        <div className="brand">
          <Mark />
          <span>nomo</span>
          <small>admin</small>
        </div>
        <nav>
          {tabs.map((t) => (
            <button key={t.id} className={tab === t.id ? 'tab active' : 'tab'} onClick={() => setTab(t.id)}>
              {t.label}
            </button>
          ))}
        </nav>
        <button
          className="ghost"
          onClick={() => {
            setToken('')
            setAuthed(false)
          }}
        >
          Выйти
        </button>
      </header>
      <main>
        {tab === 'overview' && <Overview />}
        {tab === 'drivers' && <Drivers />}
        {tab === 'orders' && <Orders />}
        {tab === 'tariffs' && <Tariffs />}
      </main>
    </div>
  )
}

function Login({ onDone }: { onDone: () => void }) {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    setBusy(true)
    setError('')
    try {
      const r = await api.login(email, password)
      setToken(r.tokens.access_token)
      onDone()
    } catch (err) {
      setError((err as Error).message)
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="login">
      <form onSubmit={submit} className="card">
        <div className="brand big">
          <Mark size={40} />
          <span>nomo</span>
        </div>
        <label>
          Email
          <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} autoComplete="username" required />
        </label>
        <label>
          Пароль
          <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} autoComplete="current-password" required />
        </label>
        {error && <p className="error">{error}</p>}
        <button className="primary" disabled={busy}>
          {busy ? 'Входим…' : 'Войти'}
        </button>
      </form>
    </div>
  )
}
