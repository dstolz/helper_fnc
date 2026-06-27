function X = filterContinuous(obj, X, opts)
%filterContinuous  Zero-phase Butterworth filtering of [nSamples x nChan] data.
%   Y = ds.filterContinuous(X) high-pass filters X (default 300 Hz) using a
%   zero-phase 4th-order Butterworth design and FILTFILT, applied column-wise
%   (time down the rows, channels across the columns).
%
%   Y = ds.filterContinuous(X, opts) with name-value options:
%     Type    "highpass" | "lowpass" | "bandpass"   (default "highpass")
%     Cutoff  scalar Hz (high/low-pass) or [lo hi] Hz (bandpass)  (default 300)
%     Order   filter order (default 4)
%     Fs      sample rate (Hz); defaults to ds.Fs
%
%   All cutoffs must be strictly below Nyquist (Fs/2). This method is static-
%   friendly: it uses only X, opts and ds.Fs, so it can be applied per file in
%   the streaming toBin path or to an in-memory matrix.
%
%   Requires the Signal Processing Toolbox (BUTTER, FILTFILT).
%
%   See also BUTTER, FILTFILT, IntanDataset.toBin.

arguments
    obj (1,1) IntanDataset
    X double
    opts.Type (1,1) string {mustBeMember(opts.Type, ["highpass","lowpass","bandpass"])} = "highpass"
    opts.Cutoff (1,:) double {mustBePositive} = 300
    opts.Order (1,1) double {mustBeInteger, mustBePositive} = 4
    opts.Fs (1,1) double = NaN
end

Fs = opts.Fs;
if isnan(Fs)
    Fs = obj.Fs;
end
if isnan(Fs) || Fs <= 0
    error('IntanDataset:filterContinuous:NoFs', ...
        'Sample rate unknown; pass opts.Fs or run refreshMetadata first.');
end

nyq = Fs / 2;

switch opts.Type
    case "highpass"
        if ~isscalar(opts.Cutoff)
            error('IntanDataset:filterContinuous:BadCutoff', ...
                'highpass requires a scalar Cutoff.');
        end
        if opts.Cutoff >= nyq
            error('IntanDataset:filterContinuous:CutoffAboveNyquist', ...
                'Cutoff (%g Hz) must be below Nyquist (%g Hz).', opts.Cutoff, nyq);
        end
        [b, a] = butter(opts.Order, opts.Cutoff / nyq, 'high');

    case "lowpass"
        if ~isscalar(opts.Cutoff)
            error('IntanDataset:filterContinuous:BadCutoff', ...
                'lowpass requires a scalar Cutoff.');
        end
        if opts.Cutoff >= nyq
            error('IntanDataset:filterContinuous:CutoffAboveNyquist', ...
                'Cutoff (%g Hz) must be below Nyquist (%g Hz).', opts.Cutoff, nyq);
        end
        [b, a] = butter(opts.Order, opts.Cutoff / nyq, 'low');

    case "bandpass"
        if numel(opts.Cutoff) ~= 2
            error('IntanDataset:filterContinuous:BadCutoff', ...
                'bandpass requires Cutoff = [low high].');
        end
        if opts.Cutoff(1) >= opts.Cutoff(2)
            error('IntanDataset:filterContinuous:BadBand', ...
                'bandpass Cutoff must be [low high] with low < high.');
        end
        if opts.Cutoff(2) >= nyq
            error('IntanDataset:filterContinuous:CutoffAboveNyquist', ...
                'Upper cutoff (%g Hz) must be below Nyquist (%g Hz).', opts.Cutoff(2), nyq);
        end
        [b, a] = butter(opts.Order, opts.Cutoff / nyq, 'bandpass');
end

% filtfilt operates column-wise -> [nSamples x nChan] is already correct
X = filtfilt(b, a, double(X));
end
