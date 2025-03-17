
function dist = dtwf(x,y)
n = size(y,1);
dist = zeros(n,1);
parfor i=1:n
    dist(i) = dtw(x,y(i,:),3);
end
end