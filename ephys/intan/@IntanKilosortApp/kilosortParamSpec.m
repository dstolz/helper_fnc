function spec = kilosortParamSpec(~)
%kilosortParamSpec  Definition of the Kilosort4 settings exposed in the GUI.
%   SPEC = obj.kilosortParamSpec() returns a struct array describing every
%   Kilosort4 parameter the Kilosort tab lets the user edit. buildKilosortTab
%   creates one control per entry, gatherKilosortConfig / applyKilosortConfig
%   round-trip them, and buildKS4Extra turns them into the settings struct that
%   is merged into KS4's settings.json.
%
%   Each entry has fields:
%     name     KS4 settings key (also the obj.ParamControls field name)
%     label    UI label
%     group    section header the control is placed under
%     kind     control/parse type, one of:
%                'int'      integer numeric field
%                'float'    real numeric field
%                'bool'     checkbox
%                'floatinf' text field; blank / Inf / Infinity -> omitted
%                           (KS4 uses its own default, typically +inf)
%                'nullable' text field; blank / null -> omitted (KS4 default)
%                'vector'   text field of comma/space-separated numbers
%     default  default value (numeric, logical, or char per kind)
%     tip      tooltip text
%
%   Defaults mirror the lab's standard KS4 configuration. No MATLAB-side
%   filtering is performed when writing the .bin; KS4 filters internally using
%   highpass_cutoff below.

s = struct('name', {}, 'label', {}, 'group', {}, 'kind', {}, 'default', {}, 'tip', {});

% --- Data ---------------------------------------------------------------
g = 'Data';
s = add(s, 'n_chan_bin', 'n_chan_bin', g, 'nullable', '',  'Channels in the .bin (blank = auto from data/probe).');
s = add(s, 'fs',         'fs',         g, 'nullable', '',  'Sample rate, Hz (blank = auto from recording).');
s = add(s, 'tmin',       'tmin',       g, 'float',    0,   'Start time, s, of data to analyze.');
s = add(s, 'tmax',       'tmax',       g, 'floatinf', 'Infinity', 'End time, s (Infinity = end of recording).');

% --- Preprocessing ------------------------------------------------------
g = 'Preprocessing';
s = add(s, 'highpass_cutoff',    'highpass_cutoff',    g, 'float',    300,        'KS4 high-pass cutoff, Hz (KS4 filters internally).');
s = add(s, 'whitening_range',    'whitening_range',    g, 'int',      32,         'Number of nearby channels for whitening.');
s = add(s, 'artifact_threshold', 'artifact_threshold', g, 'floatinf', 'Infinity', 'Blank batches above this amplitude (Infinity = off).');
s = add(s, 'nskip',              'nskip',              g, 'int',      25,         'Batch stride for computing whitening/drift.');
s = add(s, 'batch_size',         'batch_size',         g, 'int',      120000,     'Samples per processing batch.');
s = add(s, 'batch_downsampling', 'batch_downsampling', g, 'int',      1,          'Downsampling factor across batches for drift.');
s = add(s, 'nt',                 'nt',                 g, 'int',      61,         'Spike template width, samples.');
s = add(s, 'nt0min',             'nt0min',             g, 'nullable', '',         'Sample index of template peak (blank = auto).');
s = add(s, 'shift',              'shift',              g, 'nullable', '',         'Additive offset applied to data (blank = none).');
s = add(s, 'scale',              'scale',              g, 'nullable', '',         'Multiplicative scale applied to data (blank = none).');

% --- Drift correction ---------------------------------------------------
g = 'Drift correction';
s = add(s, 'nblocks',         'nblocks',         g, 'int',    0,             'Drift-correction blocks (0 = no drift correction).');
s = add(s, 'binning_depth',   'binning_depth',   g, 'float',  5,             'Depth bin size, um, for drift estimation.');
s = add(s, 'sig_interp',      'sig_interp',      g, 'float',  20,            'Interpolation sigma, um, for drift correction.');
s = add(s, 'drift_smoothing', 'drift_smoothing', g, 'vector', '0.5, 0.5, 0.5', 'Gaussian smoothing [t, x, depth] for drift.');
s = add(s, 'dmin',            'dmin',            g, 'nullable', '',          'Vertical channel spacing, um (blank = auto).');
s = add(s, 'dminx',           'dminx',           g, 'float',  32,            'Horizontal channel spacing, um.');

% --- Spike detection ----------------------------------------------------
g = 'Spike detection';
s = add(s, 'Th_universal',         'Th_universal',         g, 'float', 7,    'Threshold for universal (detection) templates.');
s = add(s, 'Th_learned',           'Th_learned',           g, 'float', 8,    'Threshold for learned templates.');
s = add(s, 'Th_single_ch',         'Th_single_ch',         g, 'float', 6,    'Single-channel detection threshold.');
s = add(s, 'nearest_chans',        'nearest_chans',        g, 'int',   10,   'Nearest channels used per template.');
s = add(s, 'nearest_templates',    'nearest_templates',    g, 'int',   58,   'Nearest templates considered per spike.');
s = add(s, 'max_channel_distance', 'max_channel_distance', g, 'float', 32,   'Max channel distance, um, for a template.');
s = add(s, 'max_peels',            'max_peels',            g, 'int',   100,  'Max matching-pursuit iterations per batch.');
s = add(s, 'templates_from_data',  'templates_from_data',  g, 'bool',  true, 'Learn templates from data (vs. fixed bank).');
s = add(s, 'n_templates',          'n_templates',          g, 'int',   6,    'Number of universal templates.');
s = add(s, 'n_pcs',                'n_pcs',                g, 'int',   6,    'PCs per channel for template features.');
s = add(s, 'template_sizes',       'template_sizes',       g, 'int',   5,    'Number of template spatial scales.');
s = add(s, 'min_template_size',    'min_template_size',    g, 'float', 15,   'Smallest template spatial scale, um.');

% --- Clustering & postproc ---------------------------------------------
g = 'Clustering & postproc';
s = add(s, 'acg_threshold',        'acg_threshold',        g, 'float', 0.2,   'Refractory ACG threshold for splits.');
s = add(s, 'ccg_threshold',        'ccg_threshold',        g, 'float', 0.25,  'CCG threshold for merges.');
s = add(s, 'cluster_neighbors',    'cluster_neighbors',    g, 'int',   10,    'Neighbors used during clustering.');
s = add(s, 'cluster_downsampling', 'cluster_downsampling', g, 'int',   20,    'Spike downsampling for clustering.');
s = add(s, 'max_cluster_subset',   'max_cluster_subset',   g, 'int',   25000, 'Max spikes used per clustering pass.');
s = add(s, 'x_centers',            'x_centers',            g, 'int',   4,     'Number of horizontal cluster centers.');
s = add(s, 'cluster_init_seed',    'cluster_init_seed',    g, 'int',   5,     'RNG seed for cluster initialization.');
s = add(s, 'duplicate_spike_ms',   'duplicate_spike_ms',   g, 'float', 0.25,  'Window, ms, for removing duplicate spikes.');
s = add(s, 'position_limit',       'position_limit',       g, 'float', 100,   'Max distance, um, for spike position estimate.');

spec = s;
end


function s = add(s, name, label, group, kind, default, tip)
%add  Append one parameter definition to the spec struct array.
s(end+1) = struct('name', name, 'label', label, 'group', group, ...
    'kind', kind, 'default', default, 'tip', tip); %#ok<AGROW>
end
