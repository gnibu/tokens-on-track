const app = require('./app');

function lazy(flag) {
  if (flag && app) {
    return import('./view');
  }
  return null;
}

module.exports = { lazy };
