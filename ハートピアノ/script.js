// ============================================================
// 1. 音を出すための準備
// ============================================================


const audioCtx = new (window.AudioContext || window.webkitAudioContext)();

const masterGain = audioCtx.createGain();

const compressor = audioCtx.createDynamicsCompressor();

compressor.threshold.setValueAtTime(-24, audioCtx.currentTime);
compressor.knee.setValueAtTime(40, audioCtx.currentTime);
compressor.ratio.setValueAtTime(12, audioCtx.currentTime);
compressor.attack.setValueAtTime(0.003, audioCtx.currentTime);
compressor.release.setValueAtTime(0.25, audioCtx.currentTime);

masterGain.gain.value = 0.25;

compressor.connect(masterGain).connect(audioCtx.destination);


// ============================================================
// 2. キーボードと音程の対応表
// ============================================================

const keyMap = {
  '2': 61,
  '3': 63,
  '5': 66,
  '6': 68,
  '7': 70,
  'q': 60,
  'w': 62,
  'e': 64,
  'r': 65,
  't': 67,
  'y': 69,
  'u': 71,
  'i': 72,
  's': 49,
  'd': 51,
  'g': 54,
  'h': 56,
  'j': 58,
  'z': 48,
  'x': 50,
  'c': 52,
  'v': 53,
  'b': 55,
  'n': 57,
  'm': 59,
  'l': 37,
  ';': 39,
  '0': 42,
  '-': 44,
  '^': 46,
  ',': 36,
  '.': 38,
  '/': 40,
  'o': 41,
  'p': 43,
  '[': 45,
  ']': 47
};

const codeToKey = {
  'Digit2': '2',
  'Digit3': '3',
  'Digit5': '5',
  'Digit6': '6',
  'Digit7': '7',
  'KeyQ': 'q',
  'KeyW': 'w',
  'KeyE': 'e',
  'KeyR': 'r',
  'KeyT': 't',
  'KeyY': 'y',
  'KeyU': 'u',
  'KeyI': 'i',
  'KeyS': 's',
  'KeyD': 'd',
  'KeyG': 'g',
  'KeyH': 'h',
  'KeyJ': 'j',
  'KeyZ': 'z',
  'KeyX': 'x',
  'KeyC': 'c',
  'KeyV': 'v',
  'KeyB': 'b',
  'KeyN': 'n',
  'KeyM': 'm',
  'KeyL': 'l',
  'Semicolon': ';',
  'Digit0': '0',
  'Minus': '-',
  'Equal': '^',
  'IntlRo': '^',
  'Comma': ',',
  'Period': '.',
  'Slash': '/',
  'KeyO': 'o',
  'KeyP': 'p',
  'BracketLeft': '[',
  'BracketRight': ']'
};


// ============================================================
// 3. 画面上の鍵盤を作成
// ============================================================

const pitchNames = [
  'ド',
  'ド#',
  'レ',
  'レ#',
  'ミ',
  'ファ',
  'ファ#',
  'ソ',
  'ソ#',
  'ラ',
  'ラ#',
  'シ'
];

const boardLayout = {
  'up-black': ['2', '3', '', '5', '6', '7'],
  'up-white': ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i'],
  'mid-black': ['s', 'd', '', 'g', 'h', 'j'],
  'mid-white': ['z', 'x', 'c', 'v', 'b', 'n', 'm'],
  'low-black': ['l', ';', '', '0', '-', '^'],
  'low-white': [',', '.', '/', 'o', 'p', '[', ']']
};

Object.keys(boardLayout).forEach((rowId) => {
  const container = document.getElementById(`row-${rowId}`);

  boardLayout[rowId].forEach((key) => {
    const keyElement = document.createElement('div');

    keyElement.className = key ? 'key' : 'key-spacer';

    if (key) {
      const midiNumber = keyMap[key];
      const pitchName = pitchNames[midiNumber % 12];

      keyElement.id = `key-${key}`;
      keyElement.innerHTML =
        `${key.toUpperCase()}<br><span class="label">${pitchName}</span>`;
    }

    container.appendChild(keyElement);
  });
});

const piano = document.getElementById('piano-visualizer');

for (let midiNumber = 36; midiNumber <= 72; midiNumber++) {
  const pianoKeyElement = document.createElement('div');

  const blackKeyPositions = [1, 3, 6, 8, 10];
  const isBlackKey = blackKeyPositions.includes(midiNumber % 12);

  pianoKeyElement.className = `p-key ${isBlackKey ? 'black' : 'white'}`;
  pianoKeyElement.id = `piano-${midiNumber}`;
  piano.appendChild(pianoKeyElement);
}


// ============================================================
// 4. 音を鳴らす処理
// ============================================================

const activeNotes = new Set();

/**
 * 指定されたMIDIノート番号の音を鳴らす。
 *
 * @param {number} midiNumber 鳴らす音のMIDIノート番号
 */
function play(midiNumber) {
  const now = audioCtx.currentTime;

  const harmonics = [
    { ratio: 1, type: 'triangle', volume: 0.4, duration: 1.2 },
    { ratio: 2, type: 'sine', volume: 0.1, duration: 0.8 },
    { ratio: 0.5, type: 'sine', volume: 0.2, duration: 1.5 }
  ];

  harmonics.forEach((harmonic) => {
    const oscillator = audioCtx.createOscillator();
    const noteGain = audioCtx.createGain();

    oscillator.type = harmonic.type;
    oscillator.frequency.value =
      440 * Math.pow(2, (midiNumber - 69) / 12) * harmonic.ratio;

    noteGain.gain.setValueAtTime(0, now);
    noteGain.gain.linearRampToValueAtTime(harmonic.volume, now + 0.005);
    noteGain.gain.exponentialRampToValueAtTime(
      0.001,
      now + harmonic.duration
    );

    oscillator.connect(noteGain).connect(compressor);

    oscillator.start();
    oscillator.stop(now + harmonic.duration);
  });

  const heart = document.getElementById('heart-container');

  if (heart) {
    const rotation = Math.random() * 20 - 10;
    heart.style.transform = `scale(1.2) rotate(${rotation}deg)`;

    setTimeout(() => {
      heart.style.transform = 'scale(1)';
    }, 80);
  }
}


// ============================================================
// 5. キーボード入力を受け取る処理
// ============================================================

window.addEventListener(
  'keydown',
  (event) => {
    const targetKey = codeToKey[event.code];
    const debug = document.getElementById('debug');

    if (debug) {
      debug.innerText =
        `AHK Code: "${event.code}" -> Key: "${targetKey || 'Miss'}"`;
    }

    if (targetKey && keyMap[targetKey]) {
      event.preventDefault();

      if (audioCtx.state === 'suspended') {
        audioCtx.resume();
      }

      if (!activeNotes.has(targetKey)) {
        const midiNumber = keyMap[targetKey];

        activeNotes.add(targetKey);
        play(midiNumber);

        document
          .getElementById(`key-${targetKey}`)
          ?.classList.add('active');

        document
          .getElementById(`piano-${midiNumber}`)
          ?.classList.add('active');
      }
    }
  },
  { passive: false }
);

window.addEventListener('keyup', (event) => {
  const targetKey = codeToKey[event.code];

  if (targetKey && activeNotes.has(targetKey)) {
    const midiNumber = keyMap[targetKey];

    activeNotes.delete(targetKey);

    document
      .getElementById(`key-${targetKey}`)
      ?.classList.remove('active');

    document
      .getElementById(`piano-${midiNumber}`)
      ?.classList.remove('active');
  }
});
