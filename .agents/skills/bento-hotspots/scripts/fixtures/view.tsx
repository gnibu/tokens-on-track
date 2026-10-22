import './app';

export function View({ items, on }: Props) {
  if (on) {
    return <ul>{items.map((i) => (i ? <li>{i}</li> : null))}</ul>;
  }
  return null;
}
