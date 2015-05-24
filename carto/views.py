from django.shortcuts import render

def home(request):
	return render(request,'carto/carto.html',locals())
