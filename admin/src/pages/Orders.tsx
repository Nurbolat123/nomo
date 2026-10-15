import { useEffect, useState } from 'react'
import { api, money, statusLabel, when, type Order } from '../api'

const statuses = ['', 'searching', 'assigned', 'arrived', 'in_progress', 'completed', 'cancelled', 'no_drivers']
const active = ['searching', 'assigned', 'arrived', 'in_progress']

export default function Orders() {
  const [status, setStatus] = useState('')
  const [phone, setPhone] = useState('')
  const [list, setList] = useState<Order[]>([])
  const [error, setError] = useState('')

  const load = () => api.orders(status, phone).then(setList).catch((e) => setError(e.message))
  useEffect(() => {
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [status])

  async function cancel(o: Order) {
    if (!confirm('Отменить заказ? Пассажир и водитель получат уведомление.')) return
    try {
      await api.cancelOrder(o.id)
      load()
    } catch (e) {
      setError((e as Error).message)
    }
  }

  return (
    <div className="stack">
      <h1>Заказы</h1>
      <form
        className="row gap"
        onSubmit={(e) => {
          e.preventDefault()
          load()
        }}
      >
        <select value={status} onChange={(e) => setStatus(e.target.value)} aria-label="Статус">
          {statuses.map((s) => (
            <option key={s} value={s}>
              {s ? statusLabel[s] : 'Все статусы'}
            </option>
          ))}
        </select>
        <input placeholder="Телефон пассажира или водителя" value={phone} onChange={(e) => setPhone(e.target.value)} />
        <button>Найти</button>
      </form>
      {error && <p className="error">{error}</p>}
      <table>
        <thead>
          <tr>
            <th>Время</th>
            <th>Маршрут</th>
            <th>Водитель</th>
            <th>Статус</th>
            <th>Сумма</th>
            <th />
          </tr>
        </thead>
        <tbody>
          {list.map((o) => (
            <tr key={o.id}>
              <td>{when(o.created_at)}</td>
              <td>
                {o.from.addr || '—'}
                <div className="muted small">→ {o.to.addr || '—'}</div>
              </td>
              <td>{o.driver ? `${o.driver.name} · ${o.driver.car_plate}` : '—'}</td>
              <td>
                <span className={`badge ${o.status}`}>{statusLabel[o.status]}</span>
                <div className="muted small">
                  {o.payment_method === 'cash' ? 'наличные' : 'карта'} · {o.payment_status}
                </div>
              </td>
              <td>{money((o.final_price ?? o.price) + o.tip)}</td>
              <td>
                {active.includes(o.status) && (
                  <button className="danger small" onClick={() => cancel(o)}>
                    Отменить
                  </button>
                )}
              </td>
            </tr>
          ))}
          {list.length === 0 && (
            <tr>
              <td colSpan={6} className="muted">
                Заказов нет
              </td>
            </tr>
          )}
        </tbody>
      </table>
    </div>
  )
}
