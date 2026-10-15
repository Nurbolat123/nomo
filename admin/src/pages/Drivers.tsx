import { useEffect, useState } from 'react'
import { api, docLabel, fileUrl, money, statusLabel, type Driver } from '../api'

const filters = [
  ['pending', 'На проверке'],
  ['approved', 'Одобрены'],
  ['new', 'Не закончили регистрацию'],
  ['rejected', 'Отклонены'],
  ['blocked', 'Заблокированы'],
  ['', 'Все'],
] as const

const allClasses = [
  ['economy', 'Эконом'],
  ['comfort', 'Комфорт'],
  ['business', 'Бизнес'],
] as const

export default function Drivers() {
  const [filter, setFilter] = useState<string>('pending')
  const [list, setList] = useState<Driver[]>([])
  const [open, setOpen] = useState<Driver | null>(null)
  const [error, setError] = useState('')

  const load = () => api.drivers(filter).then(setList).catch((e) => setError(e.message))
  useEffect(() => {
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filter])

  return (
    <div className="stack">
      <h1>Водители</h1>
      <div className="chips">
        {filters.map(([v, l]) => (
          <button key={v} className={filter === v ? 'chip active' : 'chip'} onClick={() => setFilter(v)}>
            {l}
          </button>
        ))}
      </div>
      {error && <p className="error">{error}</p>}
      <table>
        <thead>
          <tr>
            <th>Водитель</th>
            <th>Машина</th>
            <th>Статус</th>
            <th>Рейтинг</th>
            <th>Баланс</th>
          </tr>
        </thead>
        <tbody>
          {list.map((d) => (
            <tr key={d.id} onClick={() => setOpen(d)} className="clickable">
              <td>
                <b>{d.name || '—'}</b>
                <div className="muted small">{d.phone}</div>
              </td>
              <td>
                {d.car_color} {d.car_make} {d.car_model}
                <div className="muted small">{d.car_plate}</div>
              </td>
              <td>
                <span className={`badge ${d.status}`}>{statusLabel[d.status]}</span>
                {d.online && <span className="badge online">на линии</span>}
              </td>
              <td>{d.rating.toFixed(2)}</td>
              <td>{money(d.balance)}</td>
            </tr>
          ))}
          {list.length === 0 && (
            <tr>
              <td colSpan={5} className="muted">
                Никого нет
              </td>
            </tr>
          )}
        </tbody>
      </table>
      {open && (
        <DriverDrawer
          driver={open}
          onClose={() => setOpen(null)}
          onChanged={(d) => {
            setOpen(d)
            load()
          }}
        />
      )}
    </div>
  )
}

function DriverDrawer({ driver, onClose, onChanged }: { driver: Driver; onClose: () => void; onChanged: (d: Driver) => void }) {
  const [note, setNote] = useState(driver.status_note)
  const [classes, setClasses] = useState<string[]>(driver.classes)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  async function set(status: string) {
    if ((status === 'rejected' || status === 'blocked') && !note.trim()) {
      setError('Укажите причину — водитель увидит её в приложении')
      return
    }
    setBusy(true)
    setError('')
    try {
      onChanged(await api.setDriverStatus(driver.id, status, note.trim(), classes))
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="drawer-bg" onClick={onClose}>
      <aside className="drawer" onClick={(e) => e.stopPropagation()}>
        <div className="row between">
          <h2>{driver.name || 'Без имени'}</h2>
          <button className="ghost" onClick={onClose} aria-label="Закрыть">
            ✕
          </button>
        </div>
        <p className="muted">
          {driver.phone} · {statusLabel[driver.status]}
        </p>
        <p>
          {driver.car_color} {driver.car_make} {driver.car_model}, {driver.car_year} · <b>{driver.car_plate}</b>
        </p>
        <h3>Документы</h3>
        <div className="docs">
          {driver.documents.length === 0 && <p className="muted">Документы не загружены</p>}
          {driver.documents.map((d) => (
            <DocThumb key={d.id} label={docLabel[d.kind] ?? d.kind} url={d.url} />
          ))}
        </div>
        <h3>Тарифы</h3>
        <div className="chips">
          {allClasses.map(([c, l]) => (
            <label key={c} className="check">
              <input
                type="checkbox"
                checked={classes.includes(c)}
                onChange={(e) => setClasses(e.target.checked ? [...classes, c] : classes.filter((x) => x !== c))}
              />
              {l}
            </label>
          ))}
        </div>
        <label>
          Комментарий (виден водителю)
          <textarea value={note} onChange={(e) => setNote(e.target.value)} rows={2} />
        </label>
        {error && <p className="error">{error}</p>}
        <div className="row gap">
          <button className="primary" disabled={busy} onClick={() => set('approved')}>
            Одобрить
          </button>
          <button disabled={busy} onClick={() => set('rejected')}>
            Отклонить
          </button>
          <button className="danger" disabled={busy} onClick={() => set('blocked')}>
            Заблокировать
          </button>
        </div>
      </aside>
    </div>
  )
}

function DocThumb({ label, url }: { label: string; url: string }) {
  const [src, setSrc] = useState('')
  const [failed, setFailed] = useState(false)
  useEffect(() => {
    let revoke = ''
    fileUrl(url)
      .then((u) => {
        revoke = u
        setSrc(u)
      })
      .catch(() => setFailed(true))
    return () => {
      if (revoke) URL.revokeObjectURL(revoke)
    }
  }, [url])
  const isPdf = url.endsWith('.pdf')
  return (
    <figure className="doc">
      {failed ? (
        <div className="doc-ph">не открылся</div>
      ) : isPdf ? (
        <a href={src} target="_blank" rel="noreferrer" className="doc-ph">
          PDF
        </a>
      ) : src ? (
        <a href={src} target="_blank" rel="noreferrer">
          <img src={src} alt={label} />
        </a>
      ) : (
        <div className="doc-ph">…</div>
      )}
      <figcaption>{label}</figcaption>
    </figure>
  )
}
