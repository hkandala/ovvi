import { createMDX } from 'fumadocs-mdx/next';

const withMDX = createMDX();

// Old pages, still linked from released apps, installed skills and other sites.
const moved = {
  features: '',
  platform: '',
  'future-work/:path*': '',
  ui: '/guide/basics',
  'ui/window': '/guide/basics',
  'ui/program-icons': '/guide/basics#tabs',
  'ui/drag-and-drop': '/guide/basics#drag-and-drop',
  'ui/new-pane': '/guide/basics#new-pane',
  'ui/swiping': '/guide/navigate',
  'ui/chat-view': '/guide/agents#chat-view',
  status: '/guide/agents',
  'ui/browser': '/guide/browser',
  'plugins/browser': '/guide/browser',
  'plugins/default-plugins': '/guide/files-and-git',
  'ui/welcome': '/guide/setup#first-run',
  'ui/add-a-machine': '/guide/setup#remote-machines',
  machines: '/guide/setup#remote-machines',
  'ui/theme-and-accessibility': '/guide/customize',
  'ui/settings': '/reference/settings',
  telemetry: '/reference/settings',
  'ui/states': '/reference/help',
  'agent-control/:path*': '/reference/ovvi-command',
  architecture: '/reference/how-it-works',
  data: '/reference/how-it-works',
  'talking-to-herdr': '/reference/how-it-works',
  layout: '/reference/how-it-works',
  decisions: '/reference/how-it-works',
  'reference/herdr-calls': '/reference/how-it-works',
  'reference/glossary': '/reference/how-it-works#glossary',
  'plugins/packages': '/plugins/install',
  'plugins/building': '/plugins/create',
  'plugins/errors': '/plugins/create#errors-and-logs',
  'plugins/labels': '/plugins/api#labels',
};

/** @type {import('next').NextConfig} */
const config = {
  reactStrictMode: true,
  async redirects() {
    return [
      { source: '/', destination: '/docs', permanent: false },
      // folders without an index page
      { source: '/docs/guide', destination: '/docs/guide/setup', permanent: false },
      { source: '/docs/reference', destination: '/docs/reference/settings', permanent: false },
      ...Object.entries(moved).map(([from, to]) => ({
        source: `/docs/${from}`,
        destination: `/docs${to}`,
        permanent: true,
      })),
    ];
  },
};

export default withMDX(config);
