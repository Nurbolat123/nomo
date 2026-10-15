import { useEffect, useState } from 'react'
import { api, type Tariff } from '../api'

const fields: [keyof Tariff, string][] = [
  ['base_fare', 'Подача, ₸'],
  ['per_km', 'За км, ₸'],
  ['per_min', 'За минуту, ₸'],
  ['min_fare', 'Минимум, ₸'],
  ['free_wait_min', 'Бесплатное ожидание, мин'],
  ['wait_per_min', 'Ожидание, ₸/мин'],
  ['cancel_fee', 'Платная отмена, ₸'],
  ['commission_pct', 'Комиссия, %'],
]

export default function Tariffs() {
  const [list, setList] = useState<Tariff[]>([])
  const [saved, setSaved] = useState('')
  const [error, setError] = useState('')

  useEffect(() => {
    api.tariffs().then(setList).catch((e) => setError(e.message))
  }, [])

  const update = (i: number, k: keyof Tariff, v: string | boolean) =>
    setList(list.map((t, j) => (j === i ? { ...t, [k]: typeof v === 'boolean' || k === 'name' ? v : Number(v) } : t)))

  async function save(t: Tariff) {
    setError('')
    try {
      await api.saveTariff(t)
      setSaved(t.code)
      setTimeout(() => setSaved(''), 2000)
    } catch (e) {
      setError((e as Error).message)
    }
  }

  return (
    <div className="stack">
      <h1>Тарифы</h1>
      <p className="muted">Цена = подача + км × ставка + минуты × ставка, не меньше минимума, умноженная на коэффициент спроса (до ×2).</p>
      {error && <p className="error">{error}</p>}
      <div className="tariffs">
        {list.map((t, i) => (
          <div key={t.code} className="card">
            <div className="row between">
              <input className="title-input" value={t.name} onChange={(e) => update(i, 'name', e.target.value)} aria-label="Название тарифа" />
              <label className="check">
                <input type="checkbox" checked={t.active} onChange={(e) => update(i, 'active', e.target.checked)} />
                Активен
              </label>
            </div>
            <div className="grid2">
              {fields.map(([k, l]) => (
                <label key={k}>
                  {l}
                  <input type="number" min={0} value={t[k] as number} onChange={(e) => update(i, k, e.target.value)} />
                </label>
              ))}
            </div>
            <button className="primary" onClick={() => save(t)}>
              {saved === t.code ? 'Сохранено ✓' : 'Сохранить'}
            </button>
          </div>
        ))}
      </div>
    </div>
  )
}
