// Public entrance (Cloudflare Pages). Every request goes on to the ranking Worker unchanged,
// through a service binding, so the Worker still sees the player's CF-Connecting-IP.
export default {
  fetch(request, env) {
    return env.RANKING.fetch(request);
  },
};
