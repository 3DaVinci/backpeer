import { Icon } from '../components/Icon';
import { Link, useTitle } from '../lib/router';

export function NotFound() {
  useTitle('Страница не найдена');
  return (
    <div className="page">
      <div className="empty big">
        <h1>404</h1>
        <p>Такого раздела в панели нет.</p>
        <Link className="button" to="/">
          <Icon name="back" size={15} /> На обзор
        </Link>
      </div>
    </div>
  );
}
