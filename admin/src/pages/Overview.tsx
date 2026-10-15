import { useEffect, useRef, useState } from 'react'
import L from 'leaflet'
import { api, money, statusLabel, when, type LiveCar, type Order, type Stats } from '../api'

const CENTER: [number, number] = [51.2333, 51.3667] // Uralsk

export default function Overview() {
  const [days, setDays] = useState(1)
  const [stats, setStats] = useState<Stats | null>(null)
  const [cars, setCars] = useState<LiveCar[]>([])
  const [orders, setOrders] = useState<Order[]>([])
  const [error, setError] = useState('')

  useEffect(() => {
    api.stats(days).then(setStats).catch((e) => setError(e.message))
  }, [days])

  useEffect(() => {
    let alive = true
    const load = () =>
      api
        .live()
        .then((d) => {
          if (!alive) return
          setCars(d.drivers)
          setOrders(d.orders)
        })
        .catch((e) => setError(e.message))
    load()
    const id = setInterval(load, 5000)
    return () => {
      alive = false
      clearInterval(id)
    }
  }, [])

  return (
    <div className="stack">
      {error && <p className="error">{error}</p>}
      <div className="row between">
        <h1>Обзор</h1>
        <select value={days} onChange={(e) => setDays(Number(e.target.value))}>
          <option value={1}>Сутки</option>
          <option value={7}>7 дней</option>
          <option value={30}>30 дней</option>
        </select>
      </div>
      {stats && (
        <div className="kpis">
          <Kpi label="Поездок" value={String(stats.trips)} />
          <Kpi label="Оборот" value={money(stats.revenue)} />
          <Kpi label="Комиссия" value={money(stats.commission)} />
          <Kpi label="Отмены и «нет машин»" value={`${stats.cancel_rate}%`} />
          <Kpi label="Среднее время подачи" value={`${Math.round(stats.avg_pickup_s / 60)} мин`} />
          <Kpi label="Водителей на линии" value={String(stats.drivers_online)} />
          <Kpi label="Ждут проверки" value={String(stats.drivers_pending)} accent={stats.drivers_pending > 0} />
        </div>
      )}
      <div className="split">
        <LiveMap cars={cars} orders={orders} />
        <div className="card list">
          <h2>Активные заказы · {orders.length}</h2>
          {orders.length === 0 && <p className="muted">Сейчас нет активных заказов</p>}
          {orders.map((o) => (
            <div key={o.id} className="item">
              <div className="row between">
                <b>{statusLabel[o.status] ?? o.status}</b>
                <span>{money(o.price)}</span>
              </div>
              <div className="muted small">
                {when(o.created_at)} · {o.from.addr || '—'} → {o.to.addr || '—'}
              </div>
              {o.driver && (
                <div className="small">
                  {o.driver.name} · {o.driver.car_plate}
                </div>
              )}
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}

function Kpi({ label, value, accent }: { label: string; value: string; accent?: boolean }) {
  return (
    <div className={accent ? 'kpi accent' : 'kpi'}>
      <div className="kpi-value">{value}</div>
      <div className="kpi-label">{label}</div>
    </div>
  )
}

function LiveMap({ cars, orders }: { cars: LiveCar[]; orders: Order[] }) {
  const el = useRef<HTMLDivElement>(null)
  const map = useRef<L.Map | null>(null)
  const layer = useRef<L.LayerGroup | null>(null)

  useEffect(() => {
    if (!el.current || map.current) return
    map.current = L.map(el.current).setView(CENTER, 12)
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', { attribution: '© OpenStreetMap', maxZoom: 19 }).addTo(map.current)
    layer.current = L.layerGroup().addTo(map.current)
    return () => {
      map.current?.remove()
      map.current = null
    }
  }, [])

  useEffect(() => {
    const g = layer.current
    if (!g) return
    g.clearLayers()
    for (const c of cars) {
      L.circleMarker([c.lat, c.lng], { radius: 7, color: '#0A0A0A', weight: 2, fillColor: c.busy ? '#0A0A0A' : '#FFC93C', fillOpacity: 1 })
        .bindTooltip(`${c.name} · ${c.plate}${c.busy ? ' · занят' : ''}`)
        .addTo(g)
    }
    for (const o of orders) {
      if (o.status !== 'searching') continue
      L.circleMarker([o.from.lat, o.from.lng], { radius: 6, color: '#D93025', weight: 2, fillColor: '#fff', fillOpacity: 1 })
        .bindTooltip(`Ищем машину · ${o.from.addr}`)
        .addTo(g)
    }
  }, [cars, orders])

  return (
    <div className="card mapcard">
      <div className="legend">
        <span><i style={{ background: '#FFC93C' }} /> свободен</span>
        <span><i style={{ background: '#0A0A0A' }} /> занят</span>
        <span><i style={{ background: '#fff', border: '2px solid #D93025' }} /> ищет машину</span>
      </div>
      <div ref={el} className="map" />
    </div>
  )
}
