function dist = dtwf3(x,y)
% runs dtw with a maximum shift of 3 samples
n = size(y,1);
dist = zeros(n,1);
parfor i=1:n
    dist(i) = dtw(x,y(i,:),3);
end
end