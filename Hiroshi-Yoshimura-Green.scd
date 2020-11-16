(
s.boot;
s.waitForBoot({
t = TempoClock.default;

//variable tempo for rubato
~baseTempo = 1.25;
~tempoChange = 0.4;
t.tempo = ~baseTempo;
//a routine is used since this cannot be controlled using a UGen, that I know of
{var i = 0;
	loop {
		i = i + 0.1;
		t.tempo = i.sin * ~tempoChange + ~baseTempo;
		//t.tempo.postln;
		0.1.wait;
	}
}.fork;

//Electric Piano
//Two parts: a bell and a body
//modeled after 'Vintage 80's Synth' plugin on Logic
SynthDef('epiano', {|freq, gate = 1, amp = 1, pan = 0, fb = 1|

	//parameters
	var bellSinVol = 0.3;
	var bellFMVol = 0.5;
	var bellIndex = 0.732;

	var bodyVol = 0.4;
	var bodyIndex = 1;

	//panning and vibrato LFOs
	var panLFO = LFTri.kr(4.5, mul: 0.2);//slight ping-ponging
	var freqVib = SinOsc.kr(Line.kr(0, 5), mul: Line.kr(0, freq*0.003), add:freq);//vibrato-modulated freq

	//the bell is comprised of an unprocessed sine tone, and a two-oscillator FM synth
	var bellSin = SinOsc.ar(freqVib, mul: bellSinVol);//pure sine

	var bellMod = SinOsc.ar(freq, mul: freq*bellIndex);//modulator
	var cFreq = freqVib*(2 pow: 4.0833);//carrier freq is 25 semitones higher
	var bellCar = SinOsc.ar(cFreq + bellMod, mul: bellFMVol);//
	var bellEnv = EnvGen.kr(Env.adsr(0.0016, 0.330, 0.022, 0.07, 0.83), gate, doneAction:2);
	var bell = Pan2.ar(Mix.ar([bellSin, bellCar]), panLFO + pan, bellEnv*0.2);

	//the body is a two-oscillator feedback FM synth
	var fdbk = LocalIn.ar(1);
	var bodyMod = SinOsc.ar(freq, mul: Line.kr(freq*bodyIndex, 0, 3.7));//mod index decreases over sus
	var bodyCar = SinOsc.ar(freqVib + (bodyMod + fdbk*fb), mul: bodyVol);//apply feedback coefficient
	var lout = LocalOut.ar(bodyCar);
	var bodyEnv = EnvGen.kr(Env.adsr(0.0016, 3, 0, 0.099, 0.83), gate, doneAction:2);
	var body = Pan2.ar(bodyCar, panLFO + pan, bodyEnv);

	var sig = LPF1.ar(Mix.ar([body, bell]), 1000);//filter out highest sidebands

	Out.ar(0, sig*amp);
}).add;

//Slow, floating melody
//Made of a two-oscilator additive synth and Band-passed noise
SynthDef('melody', {|freq, gate = 1, amp = 1, pan = 0, dur, phase|
	var env = EnvGen.kr(Env.adsr(0.2, dur, 0.1, 0.5), gate, doneAction: 2);

	//additive synth: Sine and Triangle Waves
	//small adjustments in the freq of one Oscillator causes beats/AM vibrato
	var beatsLFO = LFTri.kr(0.05, iphase: phase, mul: 6);
	//the ratio of amplitudes amounts to the LFO depth
	var src1 = SinOsc.ar(freq + beatsLFO, mul: 0.4);
	var src2 = LFTri.ar(freq);

	//band-passed noise for whistling/echo
	var noise = BPF.ar(WhiteNoise.ar(), freq, 0.01, 2);
	var snd = Mix.ar([src1, src2, noise]) * env;

	//low-pass filter to limit the buzzy quality of the triangle wave
	var filtEnv = Env([20000, freq*7], [2]);//sweeps down
	var filt = LPF.ar(snd, filtEnv.kr());

	//reverb
	var rev = FreeVerb.ar(Mix.ar([filt, noise]),
		mix: 0.75 , room: 0.9, damp: 0.2);

	//panning slowly changes sides
	var sig = Pan2.ar(rev, pan + SinOsc.kr(0.1, (pan-0.25)*pi, 0.5, 0.25));
	Out.ar(0, sig * amp)
}).add;


//"rain-like" sound of chicken cooking in a pizza oven
b = Buffer.read(s, ("chicken_2.wav").resolveRelative);

//sample player
SynthDef('samp', {arg dur, amp = 1;
	var buf = HPF.ar(PlayBuf.ar(1, b), freq: 300);//lose fire's roar, only keep watery sounds
	var env = Env([0,1,1,0],[5,dur-15,10]);//fade in/out
	Out.ar(0, Pan2.ar(buf*env.kr(2)*amp));
}).add;

//Multi-Modulator FM Synthesis
//based on Chowning & Schottstoedt as described in Road's CMT ch6 pg242
SynthDef('mmfm', {|freq, t_gate = 1, amp = 0.1, brightness = 1, pan = 0|
	//indeces of the modulators are frequency dependent (lower->richer)
	var i1 = freq.cpsmidi.reciprocal*100;
	var i2 = freq.cpsmidi.reciprocal*100 * brightness;//arg allowing for dynamic change in timbre

	//ratio of carrier:mod1:mod2 approx. 1:3:4, with small offset to give it life
	var mod1 = SinOsc.ar(freq * 3.0172       ,  mul: freq * i1);
	var mod2 = SinOsc.ar(freq * 3.9463 + mod1,  mul: freq * i2);
	var car =  SinOsc.ar(freq          + mod2,  mul: amp      );

	//PURE MAGIC -- but a lot of it is frequency dependant
	var pluck = Pluck.ar(car, t_gate, freq.reciprocal, freq.reciprocal, freq.cpsmidi.reciprocal*60.0, 0.5);

	//reverb
	var rev = FreeVerb.ar(pluck, room: 0.6);

	//fixing a memory allocation error -- what is an easier way to free Pluck.ar?
	FreeSelf.kr(TDelay.kr(Trig.kr(pluck), 3));

	Out.ar(0, Pan2.ar(rev, pan))
}).add;

//an additive bass synth modeled on the acoustics of a pipe-marimba, i.e. open-open tubes
SynthDef('tubeperc', {|out = 0, freq = 200, gate = 1, amp = 1, pan = 0|
	var env = Env.adsr(0.01, 2, 0, 0.2);

	//adding sines
	var nPart = 11;
	var snd = Mix.fill(nPart, {arg i;
		if(i.even,//open tube supresses odd harmonics
			{SinOsc.ar(freq * (i + 1), mul: 0.05 / (i+1) )},
			{SinOsc.ar(freq * (i + 1), mul: i.linexp(1, nPart, 1, 0.1))})
	});

	var sig = Pan2.ar(snd * env.kr(2, gate: gate), pan);//panning

	Out.ar(out, sig * nPart.reciprocal * amp);
}).add;

s.sync;


//MUSICAL DATA
//floating melody
~melodyNotes = [//transcribing the notes from the Yoshimura recording, in 4 sections
	[6,7,4,2,5,6,5,8,9,10,13,15,16,12,10],
	[7,5,6,2,3,4,5,6,3,8,9,14],
	[13,12,13,9,13,12,10,7,8,9,5,3,2,3,-1,0,1,2,3,5,8,9,10],
	[14,13,10,14,13,10,16,13,12,9,10,6,12,13]
] - 1;//subtract 1 because I wrote the tonic as 1, not 0

//keep the notes grouped in the same sections, but randomize the durations
~melDur1 = (96*10).partition(~melodyNotes[0].size, 5)/10; //hold notes tied over sections
~melDur2 = (96*10).partition(~melodyNotes[1].size, 18)/10;
~melDur3 = (96*10).partition(~melodyNotes[2].size, 7)/10;
~melDur4 = (89-21*10).partition(~melodyNotes[3].size - 1, 12)/10;//subtract the silence before entrance
~melDur4.add(7);//hold the last note long

~melDurs = [~melDur1, ~melDur2, ~melDur3, ~melDur4];

//electric piano: L&R hands

a = [3, 5, 3, 2, 3, Rest()];
b = [6, 7, 6, 5, 6, Rest()];
c = [8, 7, 5];

~rightHandNotes = Array.new;
~rightHandNotes = [
	a, c,
	a, c,
	a, 8, 7, 9,
	a, c,
	b, 4, 8, 7,
	b, c,
	b, 7, 8, 9,
	a, 8, 9, 7,
	b, c[0..1],
	a, c,
	a, c[0..1],
].flatten - 1;


//follow the rule, except for the exceptions
~rhDur = Array.fill(12, {arg i;
	(0.5!4) ++ 1 ++ Rest(2) ++
	case
	{i == 8}  {[1, 2]}
	{i == 10} {[1, 6]}
	{i == 11} {Rest(4)}
	{1!3}
}).flatten;

//feedback parameter for the epiano synth
~maxFb = 3;
~fbSwitch = Pswitch([
	Pwhite(0.6,1),    //more
	Pwhite(0.1, 0.3), //some
	0,                //none
], Pseq([0,1,1,1,0,2,2,2],
	//most feedback on starting eighth notes
	//no feedback on last 3 notes of any given motif
	inf));

//amount of feedback across rhythmic motifs (11 in each of the 4 sections)
~fbLvls = [0, 0.1, 0.2, 0.0, 0.6, 1, 0.4, 0.1, 0.7, 0, 0];//0 is dry, 1 is wet

//list for use in pattern
~fbList = Array();
~fbLvls.do({|val| ~fbList = ~fbList.add(val!9)});//apply to the 9 notes of each motif
~fbList = ~fbList.flat;

~rhFb = (~fbSwitch * Pseq(~fbList)).linlin(0,1,1,~maxFb);//fb coefficient of 1 is dry in SynthDef

//Epiano left hand
i = [4, 7, 12, Rest(1)];
j = [0, 4, 7, 7,];
k = [-3, 4, 9, Rest(1)];
l = [-5, 2, 7];

~leftHandNotes = [
	i, j, i, j, i, j[0..2], i, j,
	k, l, k, l[0..1],
	k, -2, 0, 5,
	i, 14, 17,
	k, Rest(4),
	i, j, i, j[0..2],
	Rest(9)
].flatten;

//durations
~lhDur = Array.fill(13, {arg i;
	var x = case
	{[0,1,3,9 ].includes(i)}  {1!4}
	{[2,4,6,10].includes(i)}  {[1,1,2]}
	{[5,7     ].includes(i)}  {[1,3]}
	{[8,11,12 ].includes(i)}  {Rest(4)};

	1!3 ++ Rest() ++ x;})
.flatten;

//plucked accent notes
y = [Rest(1),0,Rest(6.5)];
~pluckNotes = [
	Rest(8),
	y,
	Rest(8),
	Rest(0.5), [3,2,1] +(7) -1, Rest(6),
	Rest(0.5), [3,2,1,2]    -1, Rest(5.5),
	Rest(0.5), [3,2,1,2]    -1, Rest(5.5),
	Rest(0.5), [3,2,1]      -1, Rest(6),
	Rest(1),   [3,2,3] +(7) -1, Rest(5.5),
	Rest(0.5), [3,2,1]      -1, Rest(6),
	y,
	Rest(16)
].flatten;

//all pluck durations are eight notes
~pluckDurs = Array();
~pluckNotes.do({ |val|
	if(val.isRest,
		{~pluckDurs = ~pluckDurs.add(val)},
		{~pluckDurs = ~pluckDurs.add(0.5)}
	);
});

//bass line played by 'tubeperc' SynthDef
~bassNotes = [
	Rest(32),
	Rest(1.01),4,9,    Rest(1),  -5,
	        -3,4,9 ,   Rest(1),  -5,
	        -3,4,9 ,   Rest(1),  -2,
	         0,7,12,   Rest(5),
	        -3,4,9 ,   Rest(5),

	Rest(0.99),0,      Rest(6),
	Rest(16)
];

~bassDurs = Array();
~bassNotes.do({ |val, i|
	if(val.isRest,
		{~bassDurs = ~bassDurs.add(val)},
		{if(~bassNotes[i-1] == Rest(1),//a way to get long notes where I need them
			{~bassDurs = ~bassDurs.add(4)},
			{~bassDurs = ~bassDurs.add(1)})}
	);
});



//PDEFS

//:05 fade in :10 sus :10 fade out
~sample = Pbind(
	'instrument', 'samp',
	'dur', Pseq([30], 1),
	'sustain', 1,
	'amp', 0.5);

~rightHand = Pbind(
	'instrument', 'epiano',
	'root', 9,//key of A-> root = 9
	'octave', 5,
	'degree', Pseq(~rightHandNotes),
	'dur', Pseq(~rhDur),
	'legato', Pseq(Array.fill(~rightHandNotes.size,
		{[0.7,1].wchoose([1,10].normalizeSum)})),//a way to have some notes shorter
	'fb', ~rhFb,//feedback coefficients
);
~leftHand = Pbind(
	'instrument', 'epiano',
	'root', 9,
	'octave', 4,
	'note', Pseq(~leftHandNotes),
	'dur', Pseq(~lhDur),
	'legato', 1,
);
~pluck = Pbind(
	'instrument', 'mmfm',
	'root', 9,
	'octave', 3,
	'degree', Pseq(~pluckNotes),
	'dur', Pseq(~pluckDurs),
	'brightness', Pseq([7,6,5,4,3,7], inf),//descending series to hear the player realaxing through the phrase
	'pan', -0.3
);

~melody = Pbind(
	'instrument', 'melody',
	'root', 9,
	'octave', 5,
	'legato', 1,
	'pan', Pwhite(-0.25, 0.75, inf),//each node will be panned randomly
	'phase', Pwhite(),//random so thattxthe timing of the beats is not the same for every node; see var beatsLFO in SynthDef
);

~bass = Pbind(
	'instrument', 'tubeperc',
	'root', 9,
	'octave', 1,
	'note', Pseq(~bassNotes),
	'dur', Pseq(~bassDurs),
	'pan', 0.5
);

//randomize amplitudes to give more life to the instruments
~microVar = {arg ctr;
	var dev = 0.2;
	var lo = ctr*(1-dev);
	var hi = ctr*(1+dev);
	Pseq([Pwhite(lo,hi)],inf)
};

//volume of each part in each of the four sections
~rhAmps = [0.7, 0.3, 0.2, 0.2];
~lhAmps = ~rhAmps*0.15;
~epPans = [0.1, -0.1, -0.2, -0.1];//panning for epiano
~plAmps = [0.09, 0.2, 0.159, 0.09];
~mlAmps = [0.05, 0.15, 0.2, 0.05];
~bsAmps = [0.85, 0.85, 0.6, 0.55];

//assemble it all into array
~themes = Array.fill(4, {|i|
	Ppar([
		Pbindf(~rightHand, 'amp', ~microVar.(~rhAmps[i]),
			'pan', ~epPans[i]
		),
		Pbindf(~leftHand,  'amp', ~microVar.(~lhAmps[i]),
			'pan', ~epPans[i]
		),
		Pbindf(~pluck,     'amp', ~microVar.(~plAmps[i])),
		Pbindf(~bass,      'amp', ~microVar.(~bsAmps[i]))
	]);
});

~theme = Pseq(~themes);

//assemble the melodies, which will run on in parallel
~melodies =Pseq(Array.fill(4, {|i|
	Pbindf(~melody,
		'amp', ~microVar.(~mlAmps[i]),
		'dur', Pseq(~melDurs[i]),
		'degree', Pseq(~melodyNotes[i])
)}));

//time the intro/outro sample
Ptpar([
	0, ~sample,
	7, ~theme,
	24, ~melodies,
	366, ~sample
]).play;//!!!
})
)