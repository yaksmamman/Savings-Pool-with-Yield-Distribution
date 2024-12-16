// /** @type {import('tailwindcss').Config} */
// module.exports = {
//   content: ["./src/**/*.{js,jsx}"],
//   theme: {
//     extend: {
//       animation: {
//         'fade-in': 'fadeIn 2s ease-in-out',
//       },
//       keyframes: {
//         fadeIn: {
//           '0%': { opacity: 0 },
//           '100%': { opacity: 1 },
//         },
//       },
//     },
//   },
//   plugins: [],
// };


module.exports = {
  content: ["./src/**/*.{js,jsx,ts,tsx}"],
  theme: {
    extend: {
      fontFamily: {
        futuristic: ['"Orbitron"', "arial"],
      },
    },
  },
  plugins: [],
};
