const BASE = import.meta.env.VITE_API_URL ?? ''

let token = localStorage.getItem('nomo_admin_token') ?? ''

export function setToken(t: string) {
  token = t
  if (t) localStorage.setItem('nomo_admin_token', t)
  else localStorage.removeItem('nomo_admin_token')
}

export const hasToken = () => token !== ''

export class ApiError extends Error {
  constructor(message: string, public status: number) {
    super(message)
  }
}

let onUnauthorized: () => void = () => {}
export const setUnauthorizedHandler = (f: () => void) => (onUnauthorized = f)

async function req<T>(method: string, path: string, body?: unknown): Promise<T> {
  const r = await fetch(BASE + path, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  })
  if (r.status === 401 && path !== '/v1/admin/login') {
    setToken('')
    onUnauthorized()
  }
  const data = await r.json().catch(() => null)
  if (!r.ok) throw new ApiError(data?.error?.message ?? `Ошибка ${r.status}`, r.status)
  return data as T
}

/** Loads a protected file (driver document) as an object URL. */
export async function fileUrl(path: string): Promise<string> {
  const r = await fetch(BASE + path, { headers: { Authorization: `Bearer ${token}` } })
  if (!r.ok) throw new ApiError('Файл недоступен', r.status)
  return URL.createObjectURL(await r.blob())
}

export interface Place { lat: number; lng: number; addr: string }
export interface Order {
  id: string
  status: string
  tariff: string
  from: Place
  to: Place
  price: number
  final_price: number | null
  tip: number
  cancel_fee: number
  payment_method: string
  payment_status: string
  created_at: string
  driver?: { name: string; car_plate: string; car_make: string; car_model: string }
  passenger?: { name: string }
}
export interface Document { id: string; kind: string; url: string; created_at: string }
export interface Driver {
  id: string
  phone: string
  name: string
  rating: number
  status: string
  status_note: string
  car_make: string
  car_model: string
  car_color: string
  car_plate: string
  car_year: number
  classes: string[]
  online: boolean
  busy: boolean
  balance: number
  documents: Document[]
}
export interface Tariff {
  code: string
  name: string
  base_fare: number
  per_km: number
  per_min: number
  min_fare: number
  free_wait_min: number
  wait_per_min: number
  cancel_fee: number
  commission_pct: number
  sort: number
  active: boolean
}
export interface Stats {
  trips: number
  revenue: number
  commission: number
  cancelled: number
  no_drivers: number
  cancel_rate: number
  avg_pickup_s: number
  drivers_online: number
  drivers_pending: number
}
export interface LiveCar { id: string; name: string; plate: string; lat: number; lng: number; busy: boolean }

export const api = {
  login: (email: string, password: string) =>
    req<{ tokens: { access_token: string } }>('POST', '/v1/admin/login', { email, password }),
  stats: (days: number) => req<Stats>('GET', `/v1/admin/stats?days=${days}`),
  live: () => req<{ drivers: LiveCar[]; orders: Order[] }>('GET', '/v1/admin/live'),
  drivers: (status: string) => req<Driver[]>('GET', `/v1/admin/drivers${status ? `?status=${status}` : ''}`),
  setDriverStatus: (id: string, status: string, note = '', classes?: string[]) =>
    req<Driver>('POST', `/v1/admin/drivers/${id}/status`, { status, note, classes }),
  tariffs: () => req<Tariff[]>('GET', '/v1/admin/tariffs'),
  saveTariff: (t: Tariff) => req<Tariff>('PUT', `/v1/admin/tariffs/${t.code}`, t),
  orders: (status: string, phone: string) => {
    const q = new URLSearchParams()
    if (status) q.set('status', status)
    if (phone) q.set('phone', phone)
    return req<Order[]>('GET', `/v1/admin/orders?${q}`)
  },
  cancelOrder: (id: string) => req<Order>('POST', `/v1/admin/orders/${id}/cancel`),
}

export const money = (n: number) => `${n.toLocaleString('ru-RU')} ₸`
export const when = (iso: string) =>
  new Date(iso).toLocaleString('ru-RU', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })

export const statusLabel: Record<string, string> = {
  searching: 'Поиск',
  assigned: 'Едет к клиенту',
  arrived: 'На месте',
  in_progress: 'В пути',
  completed: 'Завершён',
  cancelled: 'Отменён',
  no_drivers: 'Нет машин',
  new: 'Новый',
  pending: 'На проверке',
  approved: 'Одобрен',
  rejected: 'Отклонён',
  blocked: 'Заблокирован',
}

export const docLabel: Record<string, string> = {
  license: 'Водительское удостоверение',
  sts: 'СТС',
  osago: 'Страховка',
  car_photo: 'Фото машины',
  selfie: 'Селфи',
}
