export function timeAgo(iso: string): string {
  const then = new Date(iso).getTime();
  if (isNaN(then)) return "";
  const diff = Math.max(0, Date.now() - then);
  const min = Math.floor(diff / 60_000);
  if (min < 1) return "zojuist";
  if (min < 60) return `${min} min`;
  const uur = Math.floor(min / 60);
  if (uur < 24) return `${uur} u`;
  const dag = Math.floor(uur / 24);
  return `${dag} d`;
}
