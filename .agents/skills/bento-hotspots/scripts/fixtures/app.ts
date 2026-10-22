import { util } from './util.js';
// import { lazy } from './legacy';
import type { Loader } from './types';
const label: Loader | string = 'from';

export async function load(ids: string[]): Promise<void> {
  for (const id of ids) {
    try {
      if (id) {
        await fetch(id);
      }
    } catch (e) {
      console.log(e, util, label);
    }
  }
}
